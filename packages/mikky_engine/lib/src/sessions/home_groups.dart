import '../agents/agent.dart';

/// The groups of the agents home (UX `ux-a.html`), top to bottom.
enum HomeGroup {
  /// Needs the user: a yes / no, a question, an error.
  waiting,

  /// At work, paused by the user, or held by the subscription limit until
  /// it resets.
  working,

  /// Done or stopped, recently.
  done,

  /// Nothing new for [historyAfter]: folded by default.
  history,
}

/// Where an agent in [status], last active at [lastActivity], goes at [now].
HomeGroup homeGroupOf(
  AgentStatus status,
  DateTime lastActivity,
  DateTime now, {
  Duration historyAfter = const Duration(days: 1),
  Duration errorWaitsFor = const Duration(minutes: 30),
}) {
  final idle = now.difference(lastActivity);
  final old = idle > historyAfter;
  if (status == AgentStatus.approval || status == AgentStatus.question) return HomeGroup.waiting;
  // An error waits for the user a while; left alone, it is just a session
  // that ended badly (still shown red in « Terminés »).
  if (status == AgentStatus.error) return old ? HomeGroup.history : (idle > errorWaitsFor ? HomeGroup.done : HomeGroup.waiting);
  if (status.isBusy || status == AgentStatus.rateLimited || status == AgentStatus.paused) return HomeGroup.working;
  return old ? HomeGroup.history : HomeGroup.done;
}

/// Sorts [items] into the home groups, the most recently active first.
/// Every group is present, maybe empty.
Map<HomeGroup, List<T>> groupHome<T>(
  Iterable<T> items, {
  required AgentStatus Function(T) status,
  required DateTime Function(T) lastActivity,
  required DateTime now,
  Duration historyAfter = const Duration(days: 1),
}) {
  final groups = {for (final g in HomeGroup.values) g: <T>[]};
  for (final item in items) {
    groups[homeGroupOf(status(item), lastActivity(item), now, historyAfter: historyAfter)]!.add(item);
  }
  for (final list in groups.values) {
    list.sort((a, b) => lastActivity(b).compareTo(lastActivity(a)));
  }
  return groups;
}
