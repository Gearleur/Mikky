part of 'real_source.dart';

extension _WatchedAgents on RealAgentSource {
  /// Follows the sessions [watcher] finds. Sessions Mikky runs itself
  /// are shown once, from their live stream.
  void _follow(SessionWatcher watcher) {
    _followedAt = _now();
    for (final s in watcher.sessions.values) {
      _onWatched(s, live: false);
    }
    _subs.add(watcher.updates.listen((s) => _onWatched(s, live: true)));
    _changed();
  }

  void _onWatched(WatchedSession s, {required bool live}) {
    if (s.parent != null) {
      _subAgents.sessions[s.path] = s;
      _entries.removeWhere((e) => e.watched?.path == s.path);
      _changed();
      if (_followedAt != null && !s.modified.isBefore(_followedAt!)) {
        for (final e in _entries.where((e) => e.log.descendants.any((a) => identical(a.log, s.log)))) {
          e
            ..changedLive = true
            ..dismissed = false;
        }
      }
      return;
    }
    _subAgents.sessions.remove(s.path);
    final since = _followedAt;
    if (since != null && s.modified.isBefore(since)) live = false;
    final sessionId = s.sessionId;
    if (sessionId != null && (store?.mark('${s.provider.name}:$sessionId').forgotten ?? false)) return;
    AgentEntry? e;
    for (final x in _entries) {
      if (x.watched == s ||
          (sessionId != null && x.provider == s.provider && x.host == s.host && x.sessionId == sessionId)) {
        e = x;
      }
    }
    if (e != null && e.run != null) return;
    if (e == null) {
      final stored = sessionId == null ? null : store?.bySession(sessionId);
      e =
          AgentEntry(
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
    e
      ..watched = s
      ..failure = null;
    if (live) {
      e.changedLive = true;
      e.dismissed = false;
    }
    _changed();
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
}
