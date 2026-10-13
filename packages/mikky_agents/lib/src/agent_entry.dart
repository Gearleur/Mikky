import 'package:mikky_engine/mikky_engine.dart';

import 'acp/agent_run.dart';
import 'store.dart';
import 'watch/session_watcher.dart';

/// What the new-agent screen sends.
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
  /// Made by [RealAgentSource] only.
  AgentEntry(this.id, this.provider, this.host, this.origin, this.cwd, this.createdAt);

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

  /// The software it runs in: Mikky for its own, else what the session
  /// file says (VS Code, a terminal, the Claude or Codex app).
  AgentApp? get app => origin == AgentOrigin.mikky ? AgentApp.mikky : (log.app ?? watched?.log.app);

  /// Can take a message now: launched by Mikky and still running.
  bool get live => run?.alive ?? false;

  DateTime get lastActivity => log.descendants.fold(
    log.lastEventAt ?? watched?.modified ?? createdAt,
    (latest, child) => child.log.lastEventAt?.isAfter(latest) == true ? child.log.lastEventAt! : latest,
  );

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
