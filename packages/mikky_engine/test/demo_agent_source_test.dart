import 'dart:math' as math;

import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

AgentStatus? statusOf(DemoAgentSource s, String id) {
  for (final a in s.agents) {
    if (a.id == id) return a.status;
  }
  return null;
}

void runUntil(DemoAgentSource s, double t) {
  while (s.nextDeadline != null && s.nextDeadline! <= t) {
    s.advance(s.nextDeadline!);
  }
}

void main() {
  test('the scenario brings three agents, then an approval', () {
    final s = DemoAgentSource(random: math.Random(1))..startScenario(0);
    runUntil(s, 3);
    expect(s.agents.map((a) => a.name), ['Refacto API', 'Site vitrine', 'VPS · scraper']);
    runUntil(s, 9);
    expect(statusOf(s, 'scraper'), AgentStatus.approval);
    expect(s.agents.firstWhere((a) => a.id == 'scraper').detail, contains('cargo build --release'));
  });

  test('allowing lets the agent work, then finish, then leave', () {
    final s = DemoAgentSource(random: math.Random(1))..startScenario(0);
    runUntil(s, 9);
    expect(s.answer('scraper', AgentAnswer.allow, 10), isTrue);
    expect(statusOf(s, 'scraper'), AgentStatus.working);
    runUntil(s, 16.5);
    expect(statusOf(s, 'scraper'), AgentStatus.finished);
    runUntil(s, 16 + DemoAgentSource.finishedLinger + .1);
    expect(statusOf(s, 'scraper'), isNull);
  });

  test('the error can be retried or dismissed', () {
    final s = DemoAgentSource(random: math.Random(1))..startScenario(0);
    runUntil(s, 16);
    expect(statusOf(s, 'vitrine'), AgentStatus.error);
    expect(s.answer('vitrine', AgentAnswer.dismiss, 17), isTrue);
    expect(statusOf(s, 'vitrine'), isNull);
  });

  test('an unexpected answer falls back to dismiss; answering twice does nothing', () {
    final s = DemoAgentSource(random: math.Random(1))..startScenario(0);
    runUntil(s, 16);
    expect(s.answer('vitrine', AgentAnswer.allow, 17), isTrue);
    expect(s.answer('vitrine', AgentAnswer.allow, 17), isFalse);
  });

  test('progress grows with time and never reaches 1 before the end', () {
    final s = DemoAgentSource(random: math.Random(1))..startScenario(0);
    runUntil(s, 0);
    final a = s.agents.first;
    expect(a.progressAt(0), closeTo(.35, 1e-9));
    expect(a.progressAt(10), greaterThan(.35));
    expect(a.progressAt(1000), .97);
  });

  test('added agents finish on their own; stop clears everything', () {
    final s = DemoAgentSource(random: math.Random(1));
    final id = s.addAgent(0);
    double? finishedAt;
    for (var t = 0.0; t <= 60 && finishedAt == null; t += .5) {
      runUntil(s, t);
      if (statusOf(s, id) == AgentStatus.finished) finishedAt = t;
    }
    expect(finishedAt, inInclusiveRange(25, 45.5));
    runUntil(s, finishedAt! + DemoAgentSource.finishedLinger + .5);
    expect(statusOf(s, id), isNull);
    s.addAgent(100);
    expect(s.stop(), isTrue);
    expect(s.agents, isEmpty);
    expect(s.nextDeadline, isNull);
  });
}
