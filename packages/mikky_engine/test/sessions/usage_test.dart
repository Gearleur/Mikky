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

  test('through ACP: the context filling and the tokens of each turn', () {
    final log = replayAcp('claude_wsl_plan.jsonl');
    expect(log.contextSize, greaterThan(0));
    expect(log.contextUsed, greaterThan(0));
    expect(log.tokens, greaterThan(0));
  });
}
