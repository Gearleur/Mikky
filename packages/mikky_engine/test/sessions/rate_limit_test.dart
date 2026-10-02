import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  final seen = DateTime(2026, 9, 30, 14, 20);

  group('when the limit lifts', () {
    test('Claude, seconds after a bar', () {
      expect(limitResetOf('Claude AI usage limit reached|1759248000', seen), DateTime.fromMillisecondsSinceEpoch(1759248000 * 1000));
    });
    test('Claude, « resets 5pm »', () {
      expect(limitResetOf('5-hour limit reached ∙ resets 5pm', seen), DateTime(2026, 9, 30, 17));
      expect(limitResetOf('You’ve hit your limit · resets 5:30pm (Europe/Paris)', seen), DateTime(2026, 9, 30, 17, 30));
    });
    test('a time already past is tomorrow', () {
      expect(limitResetOf('limit reached · resets 9am', seen), DateTime(2026, 10, 1, 9));
    });
    test('Codex, « try again at » and « try again in »', () {
      expect(limitResetOf('You have hit your usage limit. Try again at 5:10 PM.', seen), DateTime(2026, 9, 30, 17, 10));
      expect(limitResetOf('Upgrade to Pro or try again in 2 hours 13 minutes.', seen), seen.add(const Duration(hours: 2, minutes: 13)));
      expect(limitResetOf('try again in 45 minutes', seen), seen.add(const Duration(minutes: 45)));
    });
    test('Codex, a weekly limit: « try again at Oct 5th, 2026 9:47 AM »', () {
      const m = 'You’ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at Oct 5th, 2026 9:47 AM.';
      expect(limitResetOf(m, seen), DateTime(2026, 10, 5, 9, 47));
      expect(limitResetOf('try again at Dec 31st 11:30 PM', seen), DateTime(2026, 12, 31, 23, 30));
    });
    test('nothing said, nothing guessed', () {
      expect(limitResetOf('Rate limit reached', seen), isNull);
      expect(limitResetOf('Limit reached at 3 files', seen), isNull);
    });
  });

  test('the line on the home and in the thread', () {
    expect(limitLine(DateTime(2026, 9, 30, 17)), 'Limite atteinte · reprend à 17 h');
    expect(limitLine(DateTime(2026, 9, 30, 17, 5)), 'Limite atteinte · reprend à 17 h 05');
    expect(limitLine(null), 'Limite atteinte');
    // Another day than when it stopped.
    expect(limitLine(DateTime(2026, 9, 30, 17), seen: seen), 'Limite atteinte · reprend à 17 h');
    expect(limitLine(DateTime(2026, 10, 1, 9), seen: seen), 'Limite atteinte · reprend demain à 9 h');
    expect(limitLine(DateTime(2026, 10, 5, 9, 47), seen: seen), 'Limite atteinte · reprend le 5 oct. à 9 h 47');
  });

  test('a session stopped by its limit says so', () {
    final log = SessionLog()
      ..applyAll([
        TurnStarted(at: seen),
        UserMessage('Traduis la doc', at: seen),
        TurnEnded(StopReason.rateLimited, message: '5-hour limit reached ∙ resets 5pm', at: seen),
      ]);
    expect(log.statusAt(seen), AgentStatus.rateLimited);
    expect(log.limitResetsAt, DateTime(2026, 9, 30, 17));
    expect(log.detail, 'Limite atteinte · reprend à 17 h');
  });
}
