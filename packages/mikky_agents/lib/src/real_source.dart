import 'dart:async';

import 'package:mikky_engine/mikky_engine.dart';

import 'acp/agent_run.dart';
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

  SessionLog get log => run?.log ?? watched?.log ?? failure ?? _empty;
  static final _empty = SessionLog();

  String? get sessionId => log.sessionId ?? watched?.sessionId;

  /// Can take a message now: launched by Mikky and still running.
  bool get live => run?.alive ?? false;

  DateTime get lastActivity => log.lastEventAt ?? watched?.modified ?? createdAt;

  String get name {
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
    DateTime Function()? now,
    this.finishedLinger = 8,
    this.staleAfter = const Duration(minutes: 15),
  }) : _now = now ?? DateTime.now {
    // An agent that never got a session (it could not start) cannot be
    // continued: forgotten.
    store?.agents.removeWhere((a) => a.sessionId == null);
    for (final a in store?.agents ?? const <StoredAgent>[]) {
      final e = AgentEntry._(a.id, a.provider, a.host, AgentOrigin.mikky, a.cwd, a.createdAt)
        ..permissions = a.permissions
        ..storedTitle = a.title;
      _entries.add(e);
      _stored[a.id] = a;
    }
  }

  /// Island clock (seconds), as the [IslandMachine] uses.
  final double Function() clock;
  final AgentSpawner spawn;
  final AgentStore? store;
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

  /// Every agent, for the home (group them with `groupHome`).
  List<AgentEntry> get entries => List.unmodifiable(_entries);

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

  static String _key(List<Agent> agents) => agents.map((a) => '${a.id}:${a.status.name}:${a.detail}').join('|');

  /// What the island last read, to tell it when that changed.
  String _islandKey = '';

  bool _onIsland(AgentEntry e, double now) {
    if (e.dismissed) return false;
    final s = e.status;
    if (s.isBusy || s == AgentStatus.rateLimited) return true;
    if (s.needsYou) return e.changedLive || e.origin == AgentOrigin.mikky;
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
      _subs.add(run.changes.listen((_) {
        _remember(e);
        _changed();
      }));
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

  /// A message for agent [id]: slipped in while it works, or the next turn.
  Future<void> send(String id, String text) async {
    final e = entry(id);
    if (e == null) return;
    if (!e.live) return resume(id, text);
    e.dismissed = false;
    await e.run!.prompt(text);
  }

  /// Stops the current work of agent [id]; it keeps its session.
  Future<void> cancel(String id) async => entry(id)?.run?.cancel();

  /// Ends agent [id] and everything it started.
  Future<void> stop(String id) async {
    await entry(id)?.run?.stop();
    _changed();
  }

  /// Ends every agent Mikky runs (when Mikky quits).
  Future<void> stopAll() async {
    for (final e in _entries) {
      await e.run?.stop();
    }
    for (final s in _subs) {
      await s.cancel();
    }
    await store?.saved;
  }

  /// Follows the sessions [watcher] finds. Sessions Mikky runs itself
  /// are shown once, from their live stream.
  void follow(SessionWatcher watcher) {
    for (final s in watcher.sessions.values) {
      _onWatched(s, live: false);
    }
    _subs.add(watcher.updates.listen((s) => _onWatched(s, live: true)));
    _changed();
  }

  void _onWatched(WatchedSession s, {required bool live}) {
    final sessionId = s.sessionId;
    AgentEntry? e;
    for (final x in _entries) {
      if (x.watched == s || (sessionId != null && x.sessionId == sessionId)) e = x;
    }
    if (e != null && e.run != null) return;
    if (e == null) {
      final stored = sessionId == null ? null : store?.bySession(sessionId);
      e = AgentEntry._(
        stored?.id ?? 'w${_ids++}',
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
    final next = (old ??
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
    for (final e in _entries) {
      final watchedOnly = e.run == null && e.failure == null;
      // Just launched: thinking until the agent says something.
      if (e.run != null && e.log.turns.isEmpty && e.status == AgentStatus.thinking) continue;
      final s = e.log.statusAt(now, staleAfter: watchedOnly ? staleAfter : null);
      if (s != e.status) _setStatus(e, s);
    }
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
      case AgentAnswer.allow || AgentAnswer.deny:
        final ok = e.run?.answer(allow: answer == AgentAnswer.allow) ?? false;
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
