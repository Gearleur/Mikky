part of 'real_source.dart';

extension _SessionRequests on RealAgentSource {
  /// The permission agent [id] asks through Claude's hooks, if any (its
  /// questions: [questionOf]).
  HookAsk? _permissionRequest(String id) {
    final ask = _hookAskOf(id);
    return ask == null || ask.isQuestion ? null : ask;
  }

  /// The question agent [id] asks through Claude's hooks, if any.
  HookAsk? _questionRequest(String id) {
    final ask = _hookAskOf(id);
    return ask != null && ask.isQuestion ? ask : null;
  }

  HookAsk? _hookAskOf(String id) {
    final sessionId = entry(id)?.sessionId;
    return sessionId == null ? null : _hookAsks[sessionId];
  }

  /// True when [answerQuestion] can reach whoever asks [questionOf].
  bool _canAnswerQuestion(String id) {
    if (hookQuestionOf(id) != null) return true;
    final e = entry(id);
    return e != null && e.live && e.log.question != null;
  }

  /// The requests waiting on `mikkyd` from Claude's hooks, all of them: each
  /// goes to its session (a new one if Mikky did not see it yet).
  void _receiveRequests(List<HookAsk> asks) {
    _hookAsks
      ..clear()
      ..addAll({for (final a in asks) a.sessionId: a});
    for (final a in asks) {
      var e = _entries.where((x) => x.provider == a.provider && x.sessionId == a.sessionId).firstOrNull;
      if (e == null) {
        e = AgentEntry('h${a.sessionId}', a.provider, AgentHost.windows, AgentOrigin.external, a.cwd, _now())
          ..failure = (SessionLog()..apply(SessionStarted(a.sessionId, cwd: a.cwd)))
          ..startedAt = clock()
          ..statusSince = clock();
        _entries.add(e);
      }
      e
        ..changedLive = true
        ..dismissed = false;
    }
    _changed();
  }

  /// How long « Répondu dans VS Code » stays as the agent's line.
  static const _noteFor = Duration(seconds: 6);

  /// Requests that ended where the session runs, or left to it after the
  /// wait (`mikkyd`'s `settled`): the agent says so for a while, as Coucou.
  void _receiveSettled(List<Object?> settled) {
    for (final s in settled.whereType<Map<Object?, Object?>>()) {
      final id = s['id'];
      if (id is! int || !_settledSeen.add(id)) continue;
      final e = _entries.where((x) => x.sessionId == s['sessionId']).lastOrNull;
      if (e == null) continue;
      _notes[e.id] = (settledNote(timedOut: s['how'] == 'timeout', app: e.log.app), _now().add(_noteFor));
    }
    _changed();
  }

  String? _noteOf(AgentEntry e) {
    final note = _notes[e.id];
    if (note == null) return null;
    if (e.status.needsYou || !_now().isBefore(note.$2)) {
      _notes.remove(e.id);
      return null;
    }
    return note.$1;
  }

  /// Project each live backend request into the same session model as ACP.
  /// Repeat refreshes do nothing; a replaced transcript gets its request too.
  void _syncRequests() {
    final logs = <SessionLog>{};
    for (final e in _entries) {
      final log = e.log;
      logs.add(log);
      final ask = _hookAsks[e.sessionId];
      if (_requestLogs.containsKey(log) && identical(_requestLogs[log], ask)) continue;
      log.setExternalRequest(ask?.event);
      _requestLogs[log] = ask;
    }
    _requestLogs.removeWhere((log, _) => !logs.contains(log));
  }
}

/// What an agent says when its request ended without Mikky: answered where
/// it runs, or, after the wait, still asked there.
String settledNote({required bool timedOut, AgentApp? app}) {
  final where = switch (app) {
    AgentApp.vscode => 'dans VS Code',
    AgentApp.claude => 'dans Claude',
    AgentApp.codex => 'dans Codex',
    _ => 'dans le terminal',
  };
  return timedOut ? 'Toujours en attente $where' : 'Répondu $where';
}
