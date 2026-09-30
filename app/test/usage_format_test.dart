import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/side/session_text.dart';
import 'package:mikky_engine/mikky_engine.dart';

void main() {
  test('tokens, in short', () {
    expect(formatTokens(950), '950');
    expect(formatTokens(1000), '1 k');
    expect(formatTokens(12345), '12 k');
    expect(formatTokens(2340), '2,3 k');
    expect(formatTokens(1200000), '1,2 M');
  });

  test('the subscription line', () {
    final reset = DateTime(2026, 9, 30, 18, 58);
    final l = LimitsSeen(
      short: LimitWindow(6, minutes: 300, resetsAt: reset),
      long: const LimitWindow(10, minutes: 10080),
    );
    expect(limitsLine(l), '6 % des 5 h, repart à 18:58 · 10 % de la semaine');
  });

  test('the usage line of an agent', () {
    final log = SessionLog()
      ..apply(const ContextUsed(34000, 100000))
      ..apply(const TokensUsed(input: 10000, output: 2300));
    expect(usageLine(log), 'Contexte 34 % · 12 k jetons');
  });
}
