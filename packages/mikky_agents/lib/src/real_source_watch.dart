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
    final previous = _watchedActivity[s.path];
    final activityChanged = previous == null || !identical(previous.$1, s.log) || previous.$2 != s.log.activityVersion;
    _watchedActivity[s.path] = (s.log, s.log.activityVersion);
    final since = _followedAt;
    final activityAt = s.log.lastActivityAt ?? s.log.lastEventAt ?? s.modified;
    live =
        live &&
        !s.replaying &&
        activityChanged &&
        s.log.activityVersion > 0 &&
        (since == null || !activityAt.isBefore(since));
    if (s.parent != null) {
      _subAgents.sessions[s.path] = s;
      _entries.removeWhere((e) => e.watched?.path == s.path);
      for (final e in _entries.where(
        (e) =>
            e.log.descendants.any((a) => identical(a.log, s.log)) ||
            (e.provider == s.provider && e.host == s.host && e.sessionId == s.parent?.session),
      )) {
        e.announceChanges = live;
        if (live) {
          e
            ..changedLive = true
            ..dismissed = false;
        }
      }
      _changed();
      return;
    }
    _subAgents.sessions.remove(s.path);
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
      ..announceChanges = live
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
