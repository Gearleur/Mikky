import '../agents/agent.dart';
import '../sessions/requests.dart';
import 'island_machine.dart';

/// What the closed island at the top shows of the agents (2026-10-12, a
/// trial on the « Petite île » board; user: « n'afficher que les bleu et
/// les états supérieurs… aussi quand il n'y a que l'état vert fini qui
/// vient d'apparaître… les étoiles peuvent se superposer avec un numéro
/// s'il y en a vraiment plein… quand il y a une orange ou rouge elle
/// apparaît à la place pour faire l'interaction »): one star per agent,
/// piled up in the middle of the pill; what needs the user drops in the
/// bubble instead.
class CompactStars {
  const CompactStars._(this.stars, this.alerts, this._finished);

  /// [justFinished]: the agent the island shows as just finished (its
  /// 5.2 s), if any.
  factory CompactStars.of(Iterable<Agent> agents, {String? justFinished}) {
    final ranked = <(int, int, Agent)>[];
    var i = 0;
    Agent? finished;
    for (final a in agents) {
      if (a.id == justFinished && a.status == AgentStatus.finished) finished = a;
      final rank = _rank(a.status);
      if (rank != null) ranked.add((rank, i++, a));
    }
    // The front first: the higher state, then the most recent.
    ranked.sort((x, y) {
      final byRank = y.$1.compareTo(x.$1);
      if (byRank != 0) return byRank;
      final byAge = y.$3.statusSince.compareTo(x.$3.statusSince);
      return byAge != 0 ? byAge : x.$2.compareTo(y.$2);
    });
    final stars = [for (final r in ranked) r.$3];
    return CompactStars._(
      stars.isEmpty && finished != null ? List.unmodifiable([finished]) : List.unmodifiable(stars),
      List.unmodifiable(requestQueue(agents, limits: false)),
      finished,
    );
  }

  /// What the island shows at this instant: its agents, the one just
  /// finished while Mikky stands for it.
  factory CompactStars.from(IslandSnapshot s) {
    final focus = s.focus;
    return CompactStars.of(s.agents, justFinished: focus?.status == AgentStatus.finished ? focus!.id : null);
  }

  static const empty = CompactStars._([], [], null);

  /// The states that go in the pile: a limit before work (thinking and
  /// searching are work); null: never there (waiting for the user, in the
  /// bubble; finished, paused, idle).
  static int? _rank(AgentStatus status) => switch (status) {
    AgentStatus.rateLimited => 1,
    AgentStatus.working || AgentStatus.thinking || AgentStatus.searching => 0,
    _ => null,
  };

  /// The pile, the front one first: limits (yellow), then agents at work
  /// (blue), the most recent first in a tie. An agent that just finished
  /// (green) only when there is nothing else.
  final List<Agent> stars;

  /// What needs the user, never in the pile but in the bubble, in the
  /// order of the requests ([requestQueue]: questions and permissions,
  /// then errors, the oldest first); the first one shows.
  final List<Agent> alerts;

  final Agent? _finished;

  /// Stars drawn at most; past that, their number beside them.
  static const shown = 3;

  /// The number beside the pile, when there are more than [shown] stars.
  int? get number => stars.length > shown ? stars.length : null;

  /// Nothing in the pile: the pill shows Mikky's name.
  bool get named => stars.isEmpty;

  /// The agent Mikky stands for, as on the island ([IslandSnapshot.focus]):
  /// the alert in the bubble, else the agent that just finished (his happy
  /// jump, even while others work), else the most recently changed agent.
  /// The pile can still put a yellow star in front of a newer blue one.
  Agent? get focus {
    final alert = alerts.firstOrNull ?? _finished;
    if (alert != null) return alert;
    Agent? latest;
    for (final a in stars) {
      if (latest == null || a.statusSince > latest.statusSince) latest = a;
    }
    return latest;
  }
}
