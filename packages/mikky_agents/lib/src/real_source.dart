import 'dart:async';
import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';

import 'acp/agent_run.dart';
import 'agent_entry.dart';
import 'daemon/daemon_run.dart';
import 'external_messages.dart';
import 'hooks.dart';
import 'limits.dart';
import 'store.dart';
import 'watch/session_watcher.dart';
import 'watch/sub_agent_sessions.dart';

part 'real_source_watch.dart';
part 'real_source_requests.dart';

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
      final e = AgentEntry(a.id, a.provider, a.host, AgentOrigin.mikky, a.cwd, a.createdAt)
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
  final _subAgents = SubAgentSessions();
  DateTime? _followedAt;
  void follow(SessionWatcher watcher) => _follow(watcher);
  final Map<String, StoredAgent> _stored = {};

  /// Permissions and questions asked through Claude's hooks, by session.
  final Map<String, HookAsk> _hookAsks = {};
  final Map<SessionLog, HookAsk?> _requestLogs = {};

  /// Absence means external injection is unavailable; a working external
  /// session must never be resumed beside the existing process.
  Future<ExternalMessage> Function(AgentEntry entry, String id, String text)? enqueueExternal;
  final Map<String, ExternalMessage> _externalMessages = {};

  List<ExternalMessage> messagesOf(String id) {
    final session = entry(id)?.sessionId;
    return _externalMessages.values.where((m) => m.sessionId == session).toList();
  }

  void externalMessages(List<ExternalMessage> messages, {bool snapshot = false}) {
    if (snapshot) {
      final ids = messages.map((m) => m.id).toSet();
      _externalMessages.removeWhere((id, _) => !ids.contains(id));
    }
    for (final m in messages) {
      if (_externalMessages[m.id]?.delivered == true && !m.delivered) continue;
      _externalMessages[m.id] = m;
    }
    while (_externalMessages.length > 256) {
      _externalMessages.remove(_externalMessages.keys.first);
    }
    _changed();
  }

  /// Sends the answer to a hook permission (`hooks.answer`): `allow`,
  /// `deny`, or null to leave it to the terminal.
  void Function(int id, String? decision)? answerHook;

  /// Sends the answers to a hook question (`hooks.answer`), by question
  /// text as Claude takes them ([HookAsk.answersFor]); null leaves it to
  /// the terminal.
  void Function(int id, Map<String, Object>? answers)? answerHookQuestion;
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

  static String _key(List<Agent> agents) =>
      agents.map((a) => '${a.id}:${a.status.name}:${a.statusSince}:${a.detail}').join('|');

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

  /// Agent [id] as the island would show it, on the island or not.
  Agent? agentOf(String id) {
    final e = entry(id);
    return e == null ? null : _agentOf(e);
  }

  HookAsk? hookAskOf(String id) => _permissionRequest(id);
  HookAsk? hookQuestionOf(String id) => _questionRequest(id);
  QuestionAsked? questionOf(String id) => entry(id)?.log.question;
  bool canAnswerRequests(String id) => _hookAskOf(id) != null || (entry(id)?.live ?? false);
  bool canLeaveInTerminal(String id) => _hookAskOf(id) != null;
  bool canAnswerQuestion(String id) => _canAnswerQuestion(id);
  void hookAsks(List<HookAsk> asks) => _receiveRequests(asks);

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
    final e = AgentEntry(id, r.provider, r.host, AgentOrigin.mikky, r.cwd, _now())
      ..permissions = r.permissions
      ..firstPrompt = r.prompt
      ..startedAt = clock()
      ..statusSince = clock()
      ..status = AgentStatus.thinking
      ..changedLive = true;
    _entries.add(e);
    _remember(e);
    store?.usedFolder(
      r.cwd,
      LaunchChoice(provider: r.provider, host: r.host, permissions: r.permissions, model: r.model),
    );
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
    await _start(
      e,
      e.cwd ?? e.log.cwd ?? '',
      mode: modeFor(e.provider, e.permissions!),
      prompt: prompt,
      resume: sessionId,
    );
  }

  Future<void> _start(
    AgentEntry e,
    String cwd, {
    required String mode,
    required String prompt,
    String? resume,
    String? model,
  }) async {
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
      e = AgentEntry(
        'm${DateTime.now().microsecondsSinceEpoch}-${_ids++}',
        provider,
        host,
        AgentOrigin.mikky,
        cwd,
        _now(),
      );
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
    if (!e.live && e.log.working) {
      final enqueue = enqueueExternal;
      if (e.provider != AgentProvider.claude || e.host != AgentHost.windows || e.sessionId == null || enqueue == null) {
        throw StateError('Cette session extérieure ne peut pas encore recevoir de message pendant son travail.');
      }
      final messageId = ExternalMessage.newId();
      final message = await enqueue(e, messageId, text);
      externalMessages([message]);
      return;
    }
    if (!e.live) return resume(id, text);
    e.dismissed = false;
    if (e.log.working) {
      await e.run!.steer(text);
    } else {
      await e.run!.prompt(text);
    }
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
    _subAgents.attach(_entries);
    _syncRequests();
    _linkForks();
    for (final e in _entries) {
      e.mark = store?.mark(e.key) ?? const SessionMark();
      final watchedOnly = e.run == null && e.failure == null;
      // Just launched: thinking until the agent says something.
      if (e.run != null && e.log.turns.isEmpty && e.status == AgentStatus.thinking) continue;
      var s = e.log.statusAt(now, staleAfter: watchedOnly ? staleAfter : null);
      if (s == AgentStatus.finished || s == AgentStatus.idle) {
        final busy = e.log.descendants
            .where((a) => a.status == ToolStatus.running && a.log.statusAt(now, staleAfter: staleAfter).isBusy)
            .firstOrNull;
        if (busy != null) s = busy.log.statusAt(now, staleAfter: staleAfter);
      }
      // Paused: once its stopped turn is over, until it is taken off hold.
      if (e.mark.pausedAt != null && !e.log.working && !s.needsYou) s = AgentStatus.paused;
      if (s != e.status) _setStatus(e, s);
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

  /// Takes back [settle]: the error or the limit waits again.
  void unsettle(String id) {
    entry(id)?.dismissed = false;
    _mark(id, (m) => m.copyWith(clearSettled: true));
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
    final hook = _hookAsks[e.sessionId];
    if (hook != null && hook.isQuestion) {
      // A question takes answers ([answerQuestion]); « Ignorer » leaves it
      // to the terminal.
      if (answer != AgentAnswer.dismiss) return false;
      return answerQuestion(id, null);
    }
    if (hook != null && answer != AgentAnswer.retry) {
      // Claude's hooks know yes and no; « Toujours » stays a yes there.
      final allow = switch (answer) {
        AgentAnswer.allow || AgentAnswer.allowAlways => true,
        AgentAnswer.deny => false,
        _ => null,
      };
      _hookAsks.remove(e.sessionId);
      answerHook?.call(hook.id, HookAsk.decision(allow: allow));
      _refresh();
      return true;
    }
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
  LimitsSeen? limitsOf(AgentProvider provider) => latestLimits(_entries, provider, now: _now());

  /// Answers agent [id]'s question ([questionOf]): the answers by
  /// [Question.key], free text by [Question.otherKey]; null skips it (ACP)
  /// or leaves it to the terminal (hooks). False if nobody asks, or if a
  /// hook question is left unanswered (it then stays).
  bool answerQuestion(String id, Map<String, Object>? answers) {
    final e = entry(id);
    if (e == null) return false;
    final hook = hookQuestionOf(id);
    if (hook != null) {
      final claude = answers == null ? null : hook.answersFor(answers);
      if (answers != null && claude == null) return false;
      _hookAsks.remove(e.sessionId);
      answerHookQuestion?.call(hook.id, claude);
      _changed();
      return true;
    }
    final ok = e.run?.answerQuestion(answers) ?? false;
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
