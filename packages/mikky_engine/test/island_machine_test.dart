import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

Agent agent(String id, AgentStatus status, {double at = 0}) =>
    Agent(id: id, name: id, status: status, startedAt: at, statusSince: at);

/// Drives an [IslandMachine] with a fake clock.
class Harness {
  Harness() : m = IslandMachine(now: 0);

  final IslandMachine m;
  double now = 0;
  final agents = <String, Agent>{};

  IslandSnapshot get s => m.snapshot;
  IslandShape get shape => s.shape;

  /// Lets time pass, firing every deadline on the way like the app does.
  void wait(double seconds) {
    final end = now + seconds;
    while (true) {
      final next = m.nextDeadline;
      if (next == null || next > end) break;
      now = next;
      m.advance(now);
    }
    now = end;
    m.advance(now);
  }

  void set(String id, AgentStatus status) {
    agents[id] = agent(id, status, at: now);
    m.setAgents(agents.values.toList(), now);
  }

  void remove(String id) {
    agents.remove(id);
    m.setAgents(agents.values.toList(), now);
  }

  void pointer({bool over = false, bool edge = false}) => m.pointer(now, overIsland: over, atEdge: edge);
}

void main() {
  test('explicit close keeps pending alerts compact despite desktop activity', () {
    final h = Harness();
    h.set('a', AgentStatus.approval);
    h.set('b', AgentStatus.question);
    h.wait(IslandTimings.bubbleLead + .1);
    h.m.close(h.now);
    expect(h.shape, IslandShape.compact);
    h.wait(IslandTimings.bubbleLead + .1);
    h.pointer();
    h.wait(1.1);
    expect(h.shape, IslandShape.compact);
    expect(h.s.pendingAlerts, 2);
    h.pointer(edge: true);
    h.wait(.7);
    expect(h.shape, IslandShape.open);
  });

  test('compact focus follows priority then newest state, not insertion order', () {
    final h = Harness();
    h.set('old', AgentStatus.working);
    h.wait(IslandTimings.bubbleLead + .1);
    h.set('new', AgentStatus.searching);
    expect(h.s.focus?.id, 'new');
    h.set('limited', AgentStatus.rateLimited);
    expect(h.s.focus?.id, 'limited');
    h.wait(IslandTimings.bubbleLead + .1);
    h.set('new', AgentStatus.thinking);
    expect(h.s.focus?.id, 'limited');
    h.set('limited', AgentStatus.idle);
    expect(h.s.focus?.id, 'new');
  });

  test('empty island also shrinks before disappearing', () {
    final h = Harness();
    h.m.click(0);
    h.m.close(0);
    expect(h.shape, IslandShape.compact);
    h.wait(IslandTimings.dismissedLinger);
    expect(h.shape, IslandShape.hidden);
  });

  test('rule 1: no agent, hidden', () {
    final h = Harness();
    expect(h.shape, IslandShape.hidden);
    expect(h.m.nextDeadline, isNull);
  });

  test('rule 2: peek from the edge, open if the cursor stays 650 ms, hide when it leaves', () {
    final h = Harness();
    h.pointer(edge: true);
    expect(h.shape, IslandShape.compact);
    expect(h.s.preview, isTrue);
    h.wait(.6);
    expect(h.shape, IslandShape.compact);
    h.wait(.1);
    expect(h.shape, IslandShape.open);
    expect(h.s.content, IslandContent.empty);

    final h2 = Harness();
    h2.pointer(edge: true);
    h2.wait(.3);
    h2.pointer();
    h2.wait(.3);
    expect(h2.shape, IslandShape.compact);
    h2.wait(.2);
    expect(h2.shape, IslandShape.hidden);
  });

  test('rule 3: agents at work, compact; rule 10: Mikky stands for the first one at work', () {
    final h = Harness();
    h.set('a', AgentStatus.idle);
    h.set('b', AgentStatus.working);
    expect(h.shape, IslandShape.compact);
    expect(h.s.focus?.id, 'b');
  });

  test('rule 4: hover opens after 200 ms and closes after leaving; click opens at once', () {
    final h = Harness();
    h.set('a', AgentStatus.working);
    h.pointer(over: true);
    h.wait(.15);
    expect(h.shape, IslandShape.compact);
    h.wait(.1);
    expect(h.shape, IslandShape.open);
    expect(h.s.openReason, OpenReason.hover);
    h.pointer();
    h.wait(.7);
    expect(h.shape, IslandShape.compact);

    h.m.click(h.now);
    expect(h.shape, IslandShape.open);
    expect(h.s.openReason, OpenReason.click);
  });

  test('rule 5: closes after 60 s without activity, with a countdown in the last 10 s; Escape closes', () {
    final h = Harness();
    h.set('a', AgentStatus.working);
    h.m.click(h.now);
    h.wait(49);
    expect(h.s.closeCountdown, isNull);
    h.wait(6);
    expect(h.s.closeCountdown, closeTo(.5, .01));
    h.wait(5.1);
    expect(h.shape, IslandShape.compact);

    h.m.click(h.now);
    h.m.close(h.now);
    expect(h.shape, IslandShape.compact);
  });

  test('closing with the cursor on the island does not reopen it on hover', () {
    final h = Harness();
    h.set('a', AgentStatus.working);
    h.pointer(over: true);
    h.wait(.3);
    h.m.close(h.now);
    h.wait(2.1);
    expect(h.shape, IslandShape.hidden);
    h.pointer();
    h.pointer(over: true);
    h.wait(.3);
    expect(h.shape, IslandShape.open);
  });

  test('rule 6: away 3 min, hidden even with agents; back at the first move', () {
    final h = Harness();
    h.set('a', AgentStatus.working);
    h.wait(179);
    expect(h.shape, IslandShape.compact);
    h.wait(2);
    expect(h.shape, IslandShape.hidden);
    h.pointer();
    expect(h.shape, IslandShape.compact);
  });

  test('rule 7: an alert shows the bubble, then opens by itself and stays until answered', () {
    final h = Harness();
    h.set('a', AgentStatus.working);
    h.set('a', AgentStatus.approval);
    expect(h.shape, IslandShape.compact);
    expect(h.s.bubble, isTrue);
    h.wait(IslandTimings.bubbleLead + .1);
    expect(h.shape, IslandShape.open);
    expect(h.s.openReason, OpenReason.alert);
    expect(h.s.focus?.id, 'a');
    h.wait(300);
    expect(h.shape, IslandShape.open);
    // Answering is a click on the island: activity.
    h.m.click(h.now);
    expect(h.shape, IslandShape.open);
    h.set('a', AgentStatus.working);
    expect(h.shape, IslandShape.compact);
    expect(h.s.bubble, isFalse);
  });

  test('rule 7: the alert opens even while away', () {
    final h = Harness();
    h.set('a', AgentStatus.working);
    h.wait(400);
    expect(h.shape, IslandShape.hidden);
    h.set('a', AgentStatus.error);
    h.wait(IslandTimings.bubbleLead + .1);
    expect(h.shape, IslandShape.open);
  });

  test('a click during the bubble opens at once', () {
    final h = Harness();
    h.set('a', AgentStatus.question);
    h.m.click(h.now);
    expect(h.shape, IslandShape.open);
    expect(h.s.openReason, OpenReason.alert);
  });

  test('Escape keeps the alert compact; a new alert opens again', () {
    final h = Harness();
    h.set('a', AgentStatus.approval);
    h.wait(IslandTimings.bubbleLead + .1);
    h.m.close(h.now);
    h.wait(5);
    expect(h.shape, IslandShape.compact);
    expect(h.s.pendingAlerts, 1);
    h.set('b', AgentStatus.error);
    h.wait(IslandTimings.bubbleLead + .1);
    expect(h.shape, IslandShape.open);
    expect(h.s.focus?.id, 'b');
  });

  test('rule 8: finished, open 5.2 s, then the agent leaves', () {
    final h = Harness();
    h.set('a', AgentStatus.working);
    h.set('a', AgentStatus.finished);
    expect(h.shape, IslandShape.open);
    expect(h.s.content, IslandContent.finished);
    expect(h.s.focus?.id, 'a');
    h.wait(5);
    expect(h.shape, IslandShape.open);
    h.wait(.3);
    expect(h.s.agents, isEmpty);
    expect(h.shape, IslandShape.hidden);
  });

  test('rule 9: alerts queue up, one at a time, in order', () {
    final h = Harness();
    h.set('a', AgentStatus.approval);
    h.set('b', AgentStatus.error);
    h.wait(IslandTimings.bubbleLead + .1);
    expect(h.s.focus?.id, 'a');
    expect(h.s.pendingAlerts, 2);
    h.set('a', AgentStatus.working);
    expect(h.shape, IslandShape.open);
    expect(h.s.focus?.id, 'b');
    h.remove('b');
    expect(h.shape, IslandShape.compact);
  });

  test('a finished agent waits for the alert to be answered', () {
    final h = Harness();
    h.set('a', AgentStatus.approval);
    h.set('b', AgentStatus.finished);
    h.wait(10);
    expect(h.s.focus?.id, 'a');
    h.set('a', AgentStatus.working);
    expect(h.s.content, IslandContent.finished);
    expect(h.s.focus?.id, 'b');
  });

  test('opened for agents, the island closes when the last one leaves', () {
    final h = Harness();
    h.set('a', AgentStatus.working);
    h.m.click(h.now);
    expect(h.shape, IslandShape.open);
    h.remove('a');
    expect(h.shape, IslandShape.hidden);
  });

  test('opened empty from the edge, it stays open empty; an agent arriving then leaving closes it', () {
    final h = Harness();
    h.pointer(edge: true);
    h.wait(.7);
    expect(h.shape, IslandShape.open);
    expect(h.s.content, IslandContent.empty);
    h.set('a', AgentStatus.working);
    expect(h.s.content, IslandContent.focus);
    h.remove('a');
    expect(h.shape, IslandShape.hidden);
  });

  test('no deadline while nothing can happen: the app can sleep', () {
    final h = Harness();
    h.set('a', AgentStatus.working);
    // Only the away rule is pending.
    expect(h.m.nextDeadline, 180);
    h.wait(200);
    expect(h.m.nextDeadline, isNull);
  });
}
