import '../support/readers/acp_reader.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Usage and limits, from the sessions recorded in the A0 probe.
void main() {
  test('Codex writes its subscription limits in its session file', () {
    final log = replayCodex('windows_steer.jsonl');
    final l = log.limits!;
    // The last reading of the session (it was 4 % at its start).
    expect(l.short!.usedPercent, 6.0);
    expect(l.short!.minutes, 300);
    expect(l.short!.resetsAt, isNotNull);
    expect(l.long!.usedPercent, 10.0);
    expect(l.long!.minutes, 10080);
    expect(l.plan, 'plus');
    expect(log.contextSize, 258400);
    expect(log.contextUsed, greaterThan(0));
  });

  test('a counter with no window (Codex « premium ») keeps the last real one', () {
    final log = SessionLog()
      ..apply(const LimitsSeen(short: LimitWindow(69, minutes: 300), long: LimitWindow(70, minutes: 10080), plan: 'plus'))
      ..apply(const LimitsSeen(plan: 'plus'));
    expect(log.limits!.short!.usedPercent, 69);
    expect(log.limits!.long!.usedPercent, 70);
  });

  test('through ACP: the context filling and the tokens of each turn', () {
    final log = replayAcp('claude_wsl_plan.jsonl');
    expect(log.contextSize, greaterThan(0));
    expect(log.contextUsed, greaterThan(0));
    expect(log.tokens, greaterThan(0));
  });

  test('the agent\'s « / » commands', () {
    final log = SessionLog()
      ..applyAll(AcpReader().read({
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 's1',
          'update': {
            'sessionUpdate': 'available_commands_update',
            'availableCommands': [
              {'name': 'compact', 'description': 'Clear conversation history but keep a summary', 'input': null},
              {'name': 'review', 'description': 'Review a pull request', 'input': {'hint': 'PR number'}},
            ],
          },
        },
      }, outgoing: false));
    expect(log.commands.map((c) => c.name), ['compact', 'review']);
    expect(log.commands[1].hint, 'PR number');
  });
}
