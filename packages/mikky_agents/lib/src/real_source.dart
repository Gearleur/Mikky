import 'dart:async';
import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';

import 'acp/agent_run.dart';
import 'daemon/daemon_run.dart';
import 'store.dart';
import 'watch/session_watcher.dart';

/// What the new-agent screen sends (MVP spec §5.3).
class LaunchRequest {
  const LaunchRequest({
    required this.provider,
    required this.host,
    required this.cwd,
    required this.prompt,
    this.permissions = PermissionMode.ask,
    this.model,
  });

  final AgentProvider provider;
  final AgentHost host;
  final String cwd;
  final String prompt;
  final PermissionMode permissions;
  final String? model;
}

/// Starts an agent adapter: the real one runs `AgentSetup.spawn` on the
/// right target; tests give a fake agent.
typedef AgentSpawner = Future<AgentRun> Function(AgentProvider provider, AgentHost host, String cwd);

/// One agent of the home: launched by Mikky ([run] while it lives) or
/// watched in Claude's / Codex's files.
class AgentEntry {
  AgentEntry._(this.id, this.provider, this.host, this.origin, this.cwd, this.createdAt);

  final String id;
  final AgentProvider provider;
  final AgentHost host;
  AgentOrigin origin;
  final String? cwd;
  final DateTime createdAt;
  PermissionMode? permissions;

  AgentRun? run;
  WatchedSession? watched;

  /// The first message, until the agent names the session.
  String? firstPrompt;

  /// The name kept in `agents.json` (the agent's title, for Mikky's own).
  String? storedTitle;

  /// State as last computed, and since when (island clock).
  AgentStatus status = AgentStatus.idle;
  double statusSince = 0;
  double startedAt = 0;

  /// The status changed while Mikky watched (not just read at start):
  /// only then does a finished agent show on the island for a moment.
  bool changedLive = false;

  /// Seen by the user (Ignorer): off the island until something new.
  bool dismissed = false;

  /// Why it could not start (adapter missing, not signed in…).
  SessionLog? failure;

  /// What the user did with it (see [SessionMark]), kept by the store.
  SessionMark mark = const SessionMark();

  /// Continued in another session (a « fork »): that one stands for both.
  String? supersededBy;

  /// The key of its [SessionMark]: the session, or the agent while it has
  /// none yet.
  String get key => sessionId == null ? id : '${provider.name}:$sessionId';

  /// The state the home sorts it by: an error settled, or a limit
  /// cancelled, by the user, with nothing new since, counts as done.
  AgentStatus get homeStatus {
    final settled = mark.settledAt;
    final settles = status == AgentStatus.error || status == AgentStatus.rateLimited;
    if (settles && settled != null && !lastActivity.isAfter(settled)) return AgentStatus.finished;
    return status;
  }

  SessionLog get log => run?.log ?? watched?.log ?? failure ?? _empty;
  static final _empty = SessionLog();

  String? get sessionId => log.sessionId ?? watched?.sessionId;

  /// Can take a message now: launched by Mikky and still running.
  bool get live => run?.alive ?? false;

  DateTime get lastActivity => log.lastEventAt ?? watched?.modified ?? createdAt;

  String get name {
    final own = mark.name;
    if (own != null && own.isNotEmpty) return own;
    // A resumed run replays no title: the file's, or the one kept, then.
    final title = log.title ?? watched?.log.title ?? storedTitle;
    if (title != null && title.isNotEmpty) return title;
    final first = firstPrompt ?? log.items.whereType<UserItem>().firstOrNull?.text;
    if (first != null && first.isNotEmpty) {
      final line = first.trim().split('\n').first;
      return line.length <= 60 ? line : '${line.substring(0, 59)}…';
    }
    final folder = cwd?.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull;
    return folder ?? 'Agent';
  }
}

/// The real agents behind the island and the home (MVP spec §5.5): those
/// Mikky launched through ACP, and the sessions found in Claude's and
/// Codex's files. Same [AgentSource] as the demo, plus [changes] because
/// real agents move on their own.
class RealAgentSource implements AgentSource {
  RealAgentSource({
    required this.clock,
    required this.spawn,
    this.store,
    this.deleteTranscript,
    DateTime Function()? now,
    this.finishedLinger = 8,
    this.staleAfter = const Duration(minutes: 15),
  }) : _now = now ?? DateTime.now {
    // An agent that never got a session (it could not start) cannot be
    // continued: forgotten.
    restoreStored();
  }

  /// Called after asynchronous store loading, before attaching live runs.
  void restoreStored() {
    for (final a in store?.agents ?? const <StoredAgent>[]) {
      // An in-flight launch in another screen may not have its session yet.
      if (a.sessionId == null) continue;
      if (_entries.any((e) => e.id == a.id)) continue;
      final e = AgentEntry._(a.id, a.provider, a.host, AgentOrigin.mikky, a.cwd, a.createdAt)
        ..permissions = a.permissions
        ..storedTitle = a.title
        ..failure = (SessionLog()..apply(SessionStarted(a.sessionId!, cwd: a.cwd, at: a.createdAt)));
      _entries.add(e);
      _stored[a.id] = a;
    }
    _changed();
  }

  /// Island clock (seconds), as the [IslandMachine] uses.
  final double Function() clock;
  final AgentSpawner spawn;
  final AgentStore? store;
  final Future<void> Function(String path)? deleteTranscript;
  final DateTime Function() _now;

  /// A finished agent stays this long on the island (seconds).
  final double finishedLinger;

  /// A watched session with no news for this long is taken as dropped.
  final Duration staleAfter;

  final List<AgentEntry> _entries = [];
  final Map<String, StoredAgent> _stored = {};
  final _changes = StreamController<void>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  int _ids = 0;

  /// Fires when agents changed by themselves: redraw, and read [agents].
  Stream<void> get changes => _changes.stream;

  /// Every agent, forgotten ones included.
  List<AgentEntry> get entries => List.unmodifiable(_entries);

  /// The agents of the home (group them with `groupHome` on
  /// [AgentEntry.homeStatus]): not forgotten, not continued elsewhere.
  /// Archived ones are in, for the « Archives » group.
  List<AgentEntry> get homeEntries => [
    for (final e in _entries)
      if (!e.mark.forgotten && e.supersededBy == null) e,
  ];

  AgentEntry? entry(String id) => _entries.where((e) => e.id == id).firstOrNull;

  /// Agents for the island: at work, waiting for the user, or just done.
  @override
  List<Agent> get agents {
    final list = _islandAgents();
    _islandKey = _key(list);
    return list;
  }

  List<Agent> _islandAgents() {
    final now = clock();
    return [
      for (final e in _entries)
        if (_onIsland(e, now)) _agentOf(e),
    ];
  }

  static String _key(List<Agent> agents) => agents.map((a) => '${a.id}:${a.status.name}:${a.statusSince}:${a.detail}').join('|');

  /// What the island last read, to tell it when that changed.
  String _islandKey = '';

  bool _onIsland(AgentEntry e, double now) {
    if (e.dismissed || e.mark.forgotten || e.mark.archived || e.supersededBy != null) return false;
    if (e.homeStatus != e.status) return false;
    final s = e.status;
    if (s.isBusy || s == AgentStatus.rateLimited) return true;
    if (s.needsYou) {
      // Same rule as the home: an error left alone leaves « En attente »
      // there, and the island with it.
      if (homeGroupOf(s, e.lastActivity, _now()) != HomeGroup.waiting) return false;
      return e.changedLive || e.origin == AgentOrigin.mikky;
    }
    return e.changedLive && s == AgentStatus.finished && now - e.statusSince < finishedLinger;
  }

  Agent _agentOf(AgentEntry e) => Agent(
    id: e.id,
    name: e.name,
    status: e.status,
    startedAt: e.startedAt,
    statusSince: e.statusSince,
    detail: e.log.detail,
    provider: e.provider,
    host: e.host,
    origin: e.origin,
    cwd: e.cwd,
    sessionId: e.sessionId,
    permissions: e.permissions,
  );

  /// Launches an agent and sends its first message. Returns its id at
  /// once; the agent shows up as it starts.
  Future<String> launch(LaunchRequest r) async {
    final id = 'm${DateTime.now().microsecondsSinceEpoch}-${_ids++}';
    final e = AgentEntry._(id, r.provider, r.host, AgentOrigin.mikky, r.cwd, _now())
      ..permissions = r.permissions
      ..firstPrompt = r.prompt
      ..startedAt = clock()
      ..statusSince = clock()
      ..status = AgentStatus.thinking
      ..changedLive = true;
    _entries.add(e);
    _remember(e);
    store?.usedFolder(r.cwd, LaunchChoice(provider: r.provider, host: r.host, permissions: r.permissions, model: r.model));
    _changed();
    await _start(e, r.cwd, mode: modeFor(r.provider, r.permissions), prompt: r.prompt, model: r.model);
    return id;
  }

  /// Continues a session: a watched one (started elsewhere, now done) or
  /// one of Mikky's from before a restart. Its thread is replayed, then
  /// [prompt] is sent.
  Future<void> resume(String id, String prompt, {PermissionMode permissions = PermissionMode.ask}) async {
    final e = entry(id);
    final sessionId = e?.sessionId;
    if (e == null || sessionId == null || e.live) return;
    e
      ..origin = AgentOrigin.mikky
      ..permissions = e.permissions ?? permissions
      ..dismissed = false;
    await _start(e, e.cwd ?? e.log.cwd ?? '', mode: modeFor(e.provider, e.permissions!), prompt: prompt, resume: sessionId);
  }

  Future<void> _start(AgentEntry e, String cwd, {required String mode, required String prompt, String? resume, String? model}) async {
    try {
      final run = await spawn(e.provider, e.host, cwd);
      e.run = run;
      _subs.add(
        run.changes.listen((_) {
          _remember(e);
          _changed();
        }),
      );
      await run.open(cwd: run.workingDirectory ?? cwd, resume: resume, mode: mode);
      if (model != null && model != run.log.modelId) await run.setModel(model);
      _remember(e);
      unawaited(run.prompt(prompt));
    } catch (err) {
      await e.run?.stop();
      e.run = null;
      e.failure = SessionLog()
        ..apply(TurnStarted(at: _now()))
        ..apply(TurnEnded(StopReason.error, message: '$err', at: _now()));
      _changed();
    }
  }

  /// Takes back an agent `mikkyd` still runs (after the app restarted):
  /// the one kept with the same session, or a new one.
  void adopt(AgentRun run, {required AgentProvider provider, required AgentHost host, String? cwd}) {
    final sessionId = run.sessionId;
    // Kept agents know their session from the store until a file shows up.
    var e = sessionId == null
        ? null
        : _entries
              .where(
                (x) =>
                    (x.run == null || (x.run is DaemonAgentRun && (x.run as DaemonAgentRun).stopped)) &&
                    x.provider == provider &&
                    x.host == host &&
                    (x.sessionId ?? _stored[x.id]?.sessionId) == sessionId,
              )
              .firstOrNull;
    if (e == null) {
      e = AgentEntry._('m${DateTime.now().microsecondsSinceEpoch}-${_ids++}', provider, host, AgentOrigin.mikky, cwd, _now());
      _entries.add(e);
    }
    final entry = e
      ..origin = AgentOrigin.mikky
      ..run = run
      ..startedAt = clock()
      ..statusSince = clock();
    _subs.add(
      run.changes.listen((_) {
        _remember(entry);
        _changed();
      }),
    );
    _remember(entry);
    _changed();
  }

  /// A message for agent [id]: slipped in while it works, or the next turn.
  /// It ends a pause.
  Future<void> send(String id, String text) async {
    final e = entry(id);
    if (e == null) return;
    if (e.run case final DaemonAgentRun run when run.disconnected) {
      throw StateError('Connexion interrompue. Attends la reconnexion avant de renvoyer un message.');
    }
    if (e.mark.pausedAt != null) _mark(id, (m) => m.copyWith(clearPaused: true));
    if (!e.live) return resume(id, text);
    e.dismissed = false;
    await e.run!.prompt(text);
  }

  /// Stops the current work of agent [id]; it keeps its session.
  Future<void> cancel(String id) async => entry(id)?.run?.cancel();

  /// Puts agent [id] on hold: its turn stops cleanly, its session stays,
  /// and it shows « En pause » until [unpause] or a new message.
  Future<void> pause(String id) async {
    final e = entry(id);
    if (e == null || !e.live) return;
    _mark(id, (m) => m.copyWith(pausedAt: _now()));
    await e.run!.cancel();
  }

  /// Takes agent [id] off hold: it goes on where it stopped (continued in
  /// its session if its process ended meanwhile).
  Future<void> unpause(String id) => send(id, 'Continue là où tu t’étais arrêté.');

  /// Ends agent [id] and everything it started.
  Future<void> stop(String id) async {
    await entry(id)?.run?.stop();
    _changed();
  }

  /// Explicit stop of all agents; closing a screen calls detach instead.
  Future<void> stopAll() async {
    for (final e in _entries) {
      await e.run?.stop();
    }
    await detach();
  }

  Future<void> detach() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await store?.saved;
  }

  /// Follows the sessions [watcher] finds. Sessions Mikky runs itself
  /// are shown once, from their live stream.
  void follow(SessionWatcher watcher) {
    _followedAt = _now();
    for (final s in watcher.sessions.values) {
      _onWatched(s, live: false);
    }
    _subs.add(watcher.updates.listen((s) => _onWatched(s, live: true)));
    _changed();
  }

  /// When [follow] began: sessions not written since are the inventory
  /// (Rust sends it as updates, and again after a reconnection), not news.
  DateTime? _followedAt;

  void _onWatched(WatchedSession s, {required bool live}) {
    final since = _followedAt;
    if (since != null && s.modified.isBefore(since)) live = false;
    final sessionId = s.sessionId;
    if (sessionId != null && (store?.mark('${s.provider.name}:$sessionId').forgotten ?? false)) return;
    AgentEntry? e;
    for (final x in _entries) {
      if (x.watched == s || (sessionId != null && x.provider == s.provider && x.host == s.host && x.sessionId == sessionId)) e = x;
    }
    if (e != null && e.run != null) return;
    if (e == null) {
      final stored = sessionId == null ? null : store?.bySession(sessionId);
      e =
          AgentEntry._(
              // Unique across runs: kept agents may carry an older one.
              stored?.id ?? 'w${DateTime.now().microsecondsSinceEpoch}-${_ids++}',
              s.provider,
              s.host,
              stored == null ? AgentOrigin.external : AgentOrigin.mikky,
              stored?.cwd ?? s.log.cwd,
              s.log.startedAt ?? s.modified,
            )
            ..permissions = stored?.permissions
            ..storedTitle = stored?.title
            ..startedAt = clock()
            ..statusSince = clock();
      if (stored != null) _entries.removeWhere((x) => x.id == stored.id);
      _entries.add(e);
    }
    e.watched = s;
    if (live) {
      e.changedLive = true;
      e.dismissed = false;
    }
    if (live) _changed();
  }

  void _remember(AgentEntry e) {
    final s = store;
    if (s == null || e.origin != AgentOrigin.mikky) return;
    final old = _stored[e.id];
    final next =
        (old ??
                StoredAgent(
                  id: e.id,
                  provider: e.provider,
                  host: e.host,
                  cwd: e.cwd ?? '',
                  permissions: e.permissions ?? PermissionMode.ask,
                  createdAt: e.createdAt,
                ))
            .copyWith(sessionId: e.sessionId, title: e.log.title ?? e.firstPrompt);
    if (old != null && old.sessionId == next.sessionId && old.title == next.title) return;
    _stored[e.id] = next;
    s.put(next);
    unawaited(s.save());
  }

  void _changed() {
    _refresh();
    _changes.add(null);
  }

  /// Recomputes every state; a change starts [Agent.statusSince] again.
  void _refresh() {
    final now = _now();
    _linkForks();
    for (final e in _entries) {
      e.mark = store?.mark(e.key) ?? const SessionMark();
      final watchedOnly = e.run == null && e.failure == null;
      // Just launched: thinking until the agent says something.
      if (e.run != null && e.log.turns.isEmpty && e.status == AgentStatus.thinking) continue;
      var s = e.log.statusAt(now, staleAfter: watchedOnly ? staleAfter : null);
      // Paused: once its stopped turn is over, until it is taken off hold.
      if (e.mark.pausedAt != null && !e.log.working && !s.needsYou) s = AgentStatus.paused;
      if (s != e.status) _setStatus(e, s);
    }
  }

  /// Sessions sharing their first message are one conversation continued
  /// (Claude's « fork »): the latest stands for all.
  void _linkForks() {
    final families = <String, List<AgentEntry>>{};
    for (final e in _entries) {
      e.supersededBy = null;
      final first = e.watched?.firstMessage;
      if (first != null) (families[first] ??= []).add(e);
    }
    for (final family in families.values) {
      if (family.length < 2) continue;
      family.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
      for (final e in family.skip(1)) {
        e.supersededBy = family.first.id;
      }
    }
  }

  // ------------------------------------------------------ user's marks

  void _mark(String id, SessionMark Function(SessionMark) change) {
    final e = entry(id);
    final s = store;
    if (e == null || s == null) return;
    s.setMark(e.key, change(s.mark(e.key)));
    unawaited(s.save());
    _changed();
  }

  /// Its own name; empty: back to the agent's title.
  void rename(String id, String name) =>
      _mark(id, (m) => name.trim().isEmpty ? m.copyWith(clearName: true) : m.copyWith(name: name.trim()));

  void setPinned(String id, bool pinned) => _mark(id, (m) => m.copyWith(pinned: pinned));

  void setArchived(String id, bool archived) => _mark(id, (m) => m.copyWith(archived: archived));

  /// The error was seen: the session counts as done until it moves again.
  void settle(String id) {
    entry(id)?.dismissed = true;
    _mark(id, (m) => m.copyWith(settledAt: _now()));
  }

  /// Deletes the session from Mikky; with [deleteFile], also Claude's or
  /// Codex's own file of it (its history is then gone for good).
  Future<void> forget(String id, {bool deleteFile = false}) async {
    final e = entry(id);
    if (e == null) return;
    await e.run?.stop();
    if (deleteFile) {
      final path = e.watched?.path;
      if (path != null) {
        if (deleteTranscript case final remove?) {
          await remove(path);
        } else {
          try {
            await File(path).delete();
          } on FileSystemException {
            // Already gone.
          }
        }
      }
    }
    store?.agents.removeWhere((a) => a.id == e.id);
    _mark(id, (m) => m.copyWith(forgotten: true, archived: false, pinned: false));
  }

  void _setStatus(AgentEntry e, AgentStatus s) {
    e
      ..status = s
      ..statusSince = clock();
  }

  @override
  bool answer(String id, AgentAnswer answer, double now) {
    final e = entry(id);
    if (e == null) return false;
    switch (answer) {
      case AgentAnswer.allow || AgentAnswer.allowAlways || AgentAnswer.deny:
        final ok = e.run?.answer(allow: answer != AgentAnswer.deny, always: answer == AgentAnswer.allowAlways) ?? false;
        if (ok) _refresh();
        return ok;
      case AgentAnswer.retry:
        if (!e.live) return false;
        unawaited(e.run!.prompt('Réessaie.'));
        return true;
      case AgentAnswer.dismiss:
        e.dismissed = true;
        return true;
    }
  }

  /// The latest subscription limits seen for [provider] (in any of its
  /// sessions), or null.
  LimitsSeen? limitsOf(AgentProvider provider) {
    LimitsSeen? best;
    for (final e in _entries) {
      if (e.provider != provider) continue;
      for (final l in [e.run?.log.limits, e.watched?.log.limits]) {
        if (l != null && (best == null || (l.at ?? DateTime(0)).isAfter(best.at ?? DateTime(0)))) best = l;
      }
    }
    if (best == null) return null;
    // Codex's last reading before it refuses can say 99 %: a turn stopped
    // by the limit since, not lifted yet, means the fullest window is full.
    final now = _now();
    final seen = best.at ?? DateTime(0);
    final stopped = _entries.any((e) {
      final resets = e.log.limitResetsAt;
      final at = e.log.lastEventAt;
      return e.provider == provider && resets != null && resets.isAfter(now) && at != null && !at.isBefore(seen);
    });
    if (!stopped) return best;
    final short = best.short, long = best.long;
    final shortFull = long == null || (short != null && short.usedPercent >= long.usedPercent);
    LimitWindow? full(LimitWindow? w) => w == null ? null : LimitWindow(100, minutes: w.minutes, resetsAt: w.resetsAt);
    return LimitsSeen(
      short: shortFull ? full(short) : short,
      long: shortFull ? long : full(long),
      plan: best.plan,
      at: best.at,
    );
  }

  /// Answers agent [id]'s question (see [AgentRun.answerQuestion]).
  bool answerQuestion(String id, Map<String, Object>? answers) {
    final ok = entry(id)?.run?.answerQuestion(answers) ?? false;
    if (ok) _changed();
    return ok;
  }

  /// When a finished agent leaves the island, or a watched session goes
  /// stale.
  @override
  double? get nextDeadline {
    final now = clock();
    final wall = _now();
    double? next;
    void consider(double t) {
      if (next == null || t < next!) next = t;
    }

    for (final e in _entries) {
      if (e.changedLive && e.status == AgentStatus.finished && !e.dismissed) {
        final t = e.statusSince + finishedLinger;
        if (t > now) consider(t);
      }
      if (e.status == AgentStatus.error && e.homeStatus == AgentStatus.error) {
        final t = now + e.lastActivity.add(homeErrorWaitsFor).difference(wall).inMilliseconds / 1000;
        if (t > now) consider(t);
      }
      final last = e.log.lastEventAt;
      if (e.run == null && e.log.working && last != null) {
        final t = now + last.add(staleAfter).difference(wall).inMilliseconds / 1000;
        if (t > now) consider(t);
      }
    }
    return next;
  }

  /// Applies what is due at [now]: states, and agents leaving the island.
  /// True if [agents] differs from what the island last read.
  @override
  bool advance(double now) {
    _refresh();
    return _key(_islandAgents()) != _islandKey;
  }
}
