import '../agents/agent.dart';

/// How pressing what an agent waits for is (2026-10-08, « le notch va
/// droit à la demande »): a question or a permission first (0), then an
/// error (1), then a subscription's limit (2); null: nothing to decide.
int? requestRank(AgentStatus status) => switch (status) {
  AgentStatus.approval || AgentStatus.question => 0,
  AgentStatus.error => 1,
  AgentStatus.rateLimited => 2,
  _ => null,
};

/// The requests waiting, in the order the open island shows them: by
/// [requestRank], then the oldest first ([Agent.statusSince]); agents in a
/// tie keep their order. [limits]: with the limits (they come last, and
/// never open the island by themselves); [skip]: agents left out (a limit
/// under the spell: nothing left to decide).
List<Agent> requestQueue(Iterable<Agent> agents, {bool limits = true, Set<String> skip = const {}}) {
  final waiting = <(int, int, Agent)>[];
  var i = 0;
  for (final a in agents) {
    final rank = requestRank(a.status);
    if (rank == null || (!limits && rank == 2) || skip.contains(a.id)) continue;
    waiting.add((rank, i++, a));
  }
  waiting.sort((x, y) {
    final byRank = x.$1.compareTo(y.$1);
    if (byRank != 0) return byRank;
    final byAge = x.$3.statusSince.compareTo(y.$3.statusSince);
    return byAge != 0 ? byAge : x.$2.compareTo(y.$2);
  });
  return [for (final w in waiting) w.$3];
}

/// Something in [queue] makes the open island go straight to it: a
/// question, a permission or an error (a limit alone does not).
bool opensOnRequest(Iterable<Agent> queue) => queue.any((a) => a.status.needsYou);
