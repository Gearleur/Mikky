import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_screens.dart';
import 'package:mikky/boards/fake_sessions.dart';
import 'package:mikky/side/question_card.dart';
import 'package:mikky/side/session_cards.dart';
import 'package:mikky/ui/foundation/tokens.dart';

void main() {
  testWidgets('an observed question offers no answer when the backend cannot receive it', (tester) async {
    final log = FakeSessions.question();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiTheme(
            ui: MikkyUi.light,
            child: AgentMock(title: 'Session observée', log: log, external: true),
          ),
        ),
      ),
    );
    expect(find.byType(QuestionCard), findsNothing);
    expect(log.question, isNotNull);
  });
  for (final question in [false, true]) {
    testWidgets('external ${question ? 'question' : 'permission'} uses the common card', (tester) async {
      final log = question ? FakeSessions.externalQuestion() : FakeSessions.externalApproval();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MikkyUiTheme(
              ui: MikkyUi.light,
              child: AgentMock(title: 'Claude extérieur', log: log, external: true, canAnswerRequests: true),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(question ? QuestionCard : AskCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
