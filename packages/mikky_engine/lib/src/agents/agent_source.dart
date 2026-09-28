import 'agent.dart';

/// Where agents come from: the demo now, real Claude Code agents at step 2.
///
/// Time-driven, without timers of its own: whoever owns the source calls
/// [advance] at [nextDeadline], so nothing runs while nothing happens.
abstract interface class AgentSource {
  /// Current agents, in the order they appeared.
  List<Agent> get agents;

  /// Sends the user's [answer] to agent [id]. Returns true if agents changed.
  bool answer(String id, AgentAnswer answer, double now);

  /// Next clock time at which the source changes by itself, or null.
  double? get nextDeadline;

  /// Applies everything due at [now]. Returns true if agents changed.
  bool advance(double now);
}
