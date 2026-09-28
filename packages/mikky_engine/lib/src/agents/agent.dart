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

  /// Refuse the command.
  deny,

  /// Run again after an error.
  retry,

  /// Acknowledge (an error, a question for later, a finished agent).
  dismiss,
}

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
  }) =>
      Agent(
        id: id,
        name: name,
        status: status ?? this.status,
        startedAt: startedAt,
        statusSince: statusSince ?? this.statusSince,
        detail: detail ?? this.detail,
        progress: clearProgress ? null : (progress ?? this.progress),
        progressRate: clearProgress ? 0 : (progressRate ?? this.progressRate),
      );

  @override
  String toString() => 'Agent($id, $status)';
}
