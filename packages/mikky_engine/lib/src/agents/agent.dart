/// What an agent is doing, as in Mochi's states (spec §5.2).
enum AgentStatus {
  working,
  thinking,
  searching,
  approval,
  question,
  error,
  finished,
  rateLimited,
  idle;

  /// The agent is blocked until the user answers: an alert (spec §5.3, 7).
  bool get needsYou => this == approval || this == question || this == error;

  /// The agent is making progress on its own.
  bool get isBusy => this == working || this == thinking || this == searching;
}

/// The user's answer to an agent that needs them.
enum AgentAnswer {
  /// Approve the command.
  allow,

  /// Approve it, and the same kind from now on (the agent's own option).
  allowAlways,

  /// Refuse the command.
  deny,

  /// Run again after an error.
  retry,

  /// Acknowledge (an error, a question for later, a finished agent).
  dismiss,
}

/// Which agent tool runs the session.
enum AgentProvider { claude, codex }

/// Where the agent runs (MVP spec §3.4). Linux comes later.
enum AgentHost { windows, wsl }

/// Launched by Mikky, or elsewhere (VS Code, a terminal) and only watched.
enum AgentOrigin { mikky, external }

/// Chosen at each launch: every request goes to the user, or the agent's
/// own automatic mode (never a mode that skips every check).
enum PermissionMode { ask, auto }

/// One agent, as seen at one instant. Immutable: a change is a new value.
class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.status,
    required this.startedAt,
    required this.statusSince,
    this.detail = '',
    this.progress,
    this.progressRate = 0,
    this.provider,
    this.host,
    this.origin = AgentOrigin.mikky,
    this.cwd,
    this.sessionId,
    this.permissions,
  });

  final String id;
  final String name;
  final AgentStatus status;

  /// Command, file, question, result or error message, shown in mono.
  final String detail;

  /// Clock time (seconds) when the agent started, and when [status] began.
  final double startedAt;
  final double statusSince;

  /// Progress 0..1 at [statusSince], growing by [progressRate] per second.
  final double? progress;
  final double progressRate;

  /// Real agents only (null in the demo).
  final AgentProvider? provider;
  final AgentHost? host;
  final AgentOrigin origin;
  final String? cwd;
  final String? sessionId;
  final PermissionMode? permissions;

  /// Progress at [now]; never reaches 1 before the agent is done.
  double? progressAt(double now) {
    final p = progress;
    if (p == null) return null;
    if (status == AgentStatus.finished) return 1;
    final v = p + progressRate * (now - statusSince);
    return v < 0 ? 0 : (v > .97 ? .97 : v);
  }

  Agent copyWith({
    AgentStatus? status,
    double? statusSince,
    String? detail,
    double? progress,
    double? progressRate,
    bool clearProgress = false,
    String? name,
    String? sessionId,
  }) =>
      Agent(
        id: id,
        name: name ?? this.name,
        status: status ?? this.status,
        startedAt: startedAt,
        statusSince: statusSince ?? this.statusSince,
        detail: detail ?? this.detail,
        progress: clearProgress ? null : (progress ?? this.progress),
        progressRate: clearProgress ? 0 : (progressRate ?? this.progressRate),
        provider: provider,
        host: host,
        origin: origin,
        cwd: cwd,
        sessionId: sessionId ?? this.sessionId,
        permissions: permissions,
      );

  @override
  String toString() => 'Agent($id, $status)';
}
