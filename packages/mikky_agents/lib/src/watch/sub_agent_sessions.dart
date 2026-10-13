import 'package:mikky_engine/mikky_engine.dart';

import '../agent_entry.dart';
import 'session_watcher.dart';

/// Keeps children even when inventory arrives before their parent.
class SubAgentSessions {
  final Map<String, WatchedSession> sessions = {};
  final Map<SessionLog, String> _versions = {};

  void attach(List<AgentEntry> entries) {
    final logs = <(AgentProvider, AgentHost, String), SessionLog>{
      for (final e in entries)
        if (e.sessionId != null) (e.provider, e.host, e.sessionId!): e.log,
      for (final s in sessions.values)
        if (s.parent != null) (s.provider, s.host, s.parent!.agent): s.log,
    };
    final children = <SessionLog, List<SubAgentLog>>{};
    for (final s in sessions.values) {
      final p = s.parent!;
      final log = logs[(s.provider, s.host, p.session)];
      if (log == null || identical(log, s.log)) continue;
      final launch = log.items.whereType<ToolItem>().where((t) => t.agent == p.agent || t.id == p.tool).firstOrNull;
      (children[log] ??= []).add(
        SubAgentLog(
          id: p.agent,
          name: p.name ?? launch?.title ?? 'Sous-agent',
          tool: p.tool,
          log: s.log,
          reportedStatus: launch?.status,
        ),
      );
    }
    for (final log in logs.values) {
      log.subAgents = children[log] ?? const [];
    }
    // Propagate child changes to the page's version, including nested agents.
    String signature(SessionLog log, Set<SessionLog> seen) {
      if (!seen.add(log)) return '';
      return log.subAgents
          .map((a) => '${a.id}:${a.name}:${a.reportedStatus}:${a.log.version}:${signature(a.log, seen)}')
          .join('|');
    }

    final visited = <SessionLog>{};
    void update(SessionLog log) {
      if (!visited.add(log)) return;
      for (final child in log.subAgents) {
        update(child.log);
      }
      final key = signature(log, {});
      if ((_versions[log] ?? '') != key) log.version++;
      _versions[log] = key;
    }

    for (final log in logs.values) {
      update(log);
    }
    _versions.removeWhere((log, _) => !visited.contains(log));
  }
}
