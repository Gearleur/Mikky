import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

Agent agent(String id, AgentStatus status, {double at = 0}) =>
    Agent(id: id, name: id, status: status, startedAt: at, statusSince: at);

List<String> ids(List<Agent> agents) => [for (final a in agents) a.id];

void main() {
  test('nobody: no star, the name', () {
    final s = CompactStars.of(const []);
    expect(s.stars, isEmpty);
    expect(s.named, isTrue);
    expect(s.focus, isNull);
  });

  test('blue and up only: paused, idle and finished stay out', () {
    final s = CompactStars.of([
      agent('p', AgentStatus.paused),
      agent('i', AgentStatus.idle),
      agent('f', AgentStatus.finished),
      agent('w', AgentStatus.working),
      agent('t', AgentStatus.thinking, at: 1),
      agent('s', AgentStatus.searching, at: 2),
    ]);
    expect(ids(s.stars), ['s', 't', 'w']);
  });

  test('a limit in front, then work, the most recent first', () {
    final s = CompactStars.of([
      agent('a', AgentStatus.working, at: 1),
      agent('b', AgentStatus.rateLimited),
      agent('c', AgentStatus.working, at: 5),
    ]);
    expect(ids(s.stars), ['b', 'c', 'a']);
    expect(s.focus!.id, 'c', reason: 'Mikky follows the newest state, independently of the pile order');
  });

  test('what needs the user goes in the bubble, never in the pile', () {
    final s = CompactStars.of([
      agent('w', AgentStatus.working),
      agent('e', AgentStatus.error, at: 1),
      agent('q', AgentStatus.approval, at: 2),
      agent('k', AgentStatus.question, at: 3),
    ]);
    expect(ids(s.stars), ['w']);
    // Questions and permissions before errors, the oldest first.
    expect(ids(s.alerts), ['q', 'k', 'e']);
    expect(s.focus!.id, 'q');
  });

  test('an alert alone: the name in the pill, the alert in the bubble', () {
    final s = CompactStars.of([agent('q', AgentStatus.approval)]);
    expect(s.named, isTrue);
    expect(ids(s.alerts), ['q']);
  });

  test('just finished: green only when nothing else is on', () {
    final alone = CompactStars.of([
      agent('f', AgentStatus.finished),
      agent('p', AgentStatus.paused),
    ], justFinished: 'f');
    expect(ids(alone.stars), ['f']);
    expect(alone.focus!.id, 'f');

    final withOthers = CompactStars.of([
      agent('f', AgentStatus.finished),
      agent('w', AgentStatus.working),
    ], justFinished: 'f');
    expect(ids(withOthers.stars), ['w']);
    // Mikky still does his happy jump for it.
    expect(withOthers.focus!.id, 'f');

    // Not shown as just finished: nothing.
    expect(CompactStars.of([agent('f', AgentStatus.finished)]).stars, isEmpty);
  });

  test('really many: a number past three stars', () {
    final few = CompactStars.of([for (var i = 0; i < 3; i++) agent('$i', AgentStatus.working)]);
    expect(few.number, isNull);
    final many = CompactStars.of([for (var i = 0; i < 7; i++) agent('$i', AgentStatus.working)]);
    expect(many.number, 7);
  });

  test('from the island: the one Mikky stands for, just finished, is green', () {
    final done = agent('f', AgentStatus.finished);
    IslandSnapshot snap(Agent? focus) => IslandSnapshot(
      shape: IslandShape.compact,
      preview: false,
      openReason: null,
      content: IslandContent.focus,
      focus: focus,
      agents: [done],
      pendingAlerts: 0,
      bubble: false,
      closeCountdown: null,
    );
    expect(CompactStars.from(snap(done)).stars, [done]);
    expect(CompactStars.from(snap(null)).stars, isEmpty);
  });
}
