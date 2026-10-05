import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/side/home_screen.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// What the notch shows from the agents, without a screen.
void main() {
  final now = DateTime(2026, 10, 5, 15);

  group('the task Mikky looks at', () {
    String? watched(List<(String, AgentStatus, int)> agents) => watchedOf(
      agents,
      status: (a) => a.$2,
      lastActivity: (a) => now.subtract(Duration(minutes: a.$3)),
      now: now,
    )?.$1;

    test('the latest at work or waiting, before any finished one', () {
      expect(watched([('a', AgentStatus.finished, 0), ('b', AgentStatus.working, 30), ('c', AgentStatus.approval, 5)]), 'c');
    });

    test('else the latest that ended in the last 10 minutes', () {
      expect(watched([('a', AgentStatus.finished, 3), ('b', AgentStatus.error, 8)]), 'a');
      expect(watched([('a', AgentStatus.finished, 11)]), isNull);
    });

    test('a stopped or paused agent is not watched', () {
      expect(watched([('a', AgentStatus.idle, 0), ('b', AgentStatus.paused, 0)]), isNull);
    });
  });

  test('the line under an app: what it does, or how it ended', () {
    final log = SessionLog()
      ..applyAll([
        TurnStarted(at: now),
        UserMessage('Go', at: now),
        const ToolCallEvent('1', kind: ToolKind.read, title: 'Lire api.md', status: ToolStatus.running),
      ]);
    expect(appLine(AgentStatus.working, log, now, now), 'Lire api.md');
    expect(appLine(AgentStatus.finished, log, now.subtract(const Duration(minutes: 5)), now), 'Terminée · il y a 5 min');
    expect(appLine(AgentStatus.question, log, now, now), 'Te pose une question');
  });
}
