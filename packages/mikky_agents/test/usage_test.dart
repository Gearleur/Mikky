import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  test('Claude\'s usage from its status line becomes its limits', () {
    final source = RealAgentSource(clock: () => 0, spawn: (_, _, _) => throw UnimplementedError());
    expect(source.limitsOf(AgentProvider.claude), isNull);
    source.usageReported({'claude': <String, Object?>{}});
    expect(source.limitsOf(AgentProvider.claude), isNull);
    source.usageReported({
      'claude': {
        'fiveHour': {'usedPercent': 23.5, 'resetsAt': 1738425600},
        'sevenDay': {'usedPercent': 41.2, 'resetsAt': null},
        'at': '2026-10-25T10:00:00Z',
      },
    });
    final limits = source.limitsOf(AgentProvider.claude)!;
    expect(limits.short?.usedPercent, 23.5);
    expect(limits.short?.minutes, 300);
    expect(limits.short?.resetsAt, DateTime.fromMillisecondsSinceEpoch(1738425600 * 1000));
    expect(limits.long?.usedPercent, 41.2);
    expect(limits.long?.minutes, 10080);
    expect(limits.long?.resetsAt, isNull);
    expect(source.limitsOf(AgentProvider.codex), isNull);
  });
}
