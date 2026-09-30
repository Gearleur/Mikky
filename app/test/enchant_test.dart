import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/agents/enchant.dart';

/// « Ensorcelé »: stopped by its limit, the agent is relaunched by itself
/// once the limit lifts; hit again, it waits for the next reset. (Test
/// timers are simulated: `tester.pump` moves time on.)
void main() {
  testWidgets('relaunches after the reset, and again if the limit is back', (tester) async {
    final spells = Enchantments.instance;
    final sent = <String>[];
    Future<void> send(String t) async => sent.add(t);
    final now = DateTime(2026, 9, 30, 14);
    spells.enchant('a', now.add(const Duration(hours: 3)), send, now: now);
    expect(spells.isOn('a'), isTrue);
    expect(spells.relaunchAt('a'), now.add(const Duration(hours: 3, minutes: 1)));
    await tester.pump(const Duration(hours: 3));
    expect(sent, isEmpty);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(sent, [Enchantments.resumeMessage]);
    // Sent, waiting to see it through.
    expect(spells.isOn('a'), isTrue);
    expect(spells.relaunchAt('a'), isNull);
    // The limit again: waits for the next reset (unknown: 30 min).
    spells.limitedAgain('a', DateTime.now().add(const Duration(seconds: 1)), null, send);
    expect(spells.relaunchAt('a'), isNotNull);
    await tester.pump(const Duration(minutes: 32));
    expect(sent, hasLength(2));
    // Through: the spell is over.
    spells.done('a');
    expect(spells.isOn('a'), isFalse);
  });

  testWidgets('cancelled: nothing is sent', (tester) async {
    final spells = Enchantments.instance;
    final sent = <String>[];
    spells.enchant('b', null, (t) async => sent.add(t), now: DateTime(2026, 9, 30, 14));
    spells.cancel('b');
    await tester.pump(const Duration(hours: 1));
    expect(sent, isEmpty);
    expect(spells.isOn('b'), isFalse);
  });
}
