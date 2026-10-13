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
