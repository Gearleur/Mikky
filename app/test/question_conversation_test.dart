import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/fake_sessions.dart';
import 'package:mikky/home/home_app_tile.dart';
import 'package:mikky/home/home_view.dart';
import 'package:mikky/home/notch_request.dart';
import 'package:mikky/side/question_card.dart';
import 'package:mikky/ui/content/side.dart';
import 'package:mikky/ui/controls/step_tabs.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'load_fonts.dart';

Widget _page(SessionLog log, {required MikkyUi ui, ValueChanged<Map<String, Object>?>? answer}) => WidgetsApp(
  color: ui.island,
  builder: (context, _) => MikkyUiScope(
    ui: ui,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: const Key('question-page'),
        child: ColoredBox(
          color: ui.island,
          child: HomeView(
            animate: false,
            request: NotchRequest(
              name: 'Mikky · Revoir les questions de la notch',
              log: log,
              provider: AgentProvider.codex,
              app: AgentApp.codex,
              onAnswerQuestion: answer,
              onLater: () {},
              onOpen: () {},
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('an oversized form opens at its question and wheel movement stays bounded', (tester) async {
    final log = SessionLog()
      ..applyAll([
        const TurnStarted(),
        const UserMessage('Contexte de la longue question'),
        QuestionAsked(
          'long',
          message: 'Lis cette question avant de répondre',
          questions: [
            Question(
              'long',
              text: 'Lis cette question avant de répondre',
              multiple: true,
              choices: [
                for (var i = 0; i < 18; i++)
                  QuestionChoice(
                    'Choix $i',
                    'Une description détaillée sur plusieurs lignes pour lire avant de choisir.',
                  ),
              ],
            ),
          ],
        ),
      ]);
    await tester.pumpWidget(_page(log, ui: MikkyUi.light, answer: (_) {}));
    await tester.pumpAndSettle();
    final card = tester.widget<QuestionCard>(find.byType(QuestionCard));
    final viewport = tester.getRect(find.byType(CustomScrollView));
    final title = tester.getRect(find.text('Lis cette question avant de répondre'));
    expect(title.top, greaterThanOrEqualTo(viewport.top));
    expect(title.bottom, lessThan(viewport.bottom));
    final before = card.scroll!.offset;
    await tester.sendEventToBinding(PointerScrollEvent(position: viewport.center, scrollDelta: const Offset(0, 300)));
    await tester.pumpAndSettle();
    expect(card.scroll!.offset - before, inInclusiveRange(1, 48));
    await tester.tap(find.text('Question'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Lis cette question avant de répondre')).top, title.top);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing a question keeps the same viewport and a static notch', (tester) async {
    await tester.pumpWidget(_page(FakeSessions.questions(), ui: MikkyUi.light, answer: (_) {}));
    await tester.pumpAndSettle();
    final card = tester.widget<QuestionCard>(find.byType(QuestionCard));
    final position = card.scroll!.position;
    final frame = tester.getRect(find.byType(HomeView));
    final header = tester.getRect(find.text('Mikky · Revoir les questions de la notch'));
    await tester.tap(find.text('SQLite'));
    for (final elapsed in [Duration.zero, const Duration(milliseconds: 16), const Duration(milliseconds: 160)]) {
      await tester.pump(elapsed);
      expect(tester.widget<QuestionCard>(find.byType(QuestionCard)).scroll!.position, same(position));
      expect(tester.getRect(find.byType(HomeView)), frame);
      expect(tester.getRect(find.text('Mikky · Revoir les questions de la notch')), header);
      expect(position.isScrollingNotifier.value, isFalse);
    }
    expect(find.text('Quand lancer les tâches ?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('identity and actions stay visible while reading a long conversation and returning to the form', (
    tester,
  ) async {
    final log = SessionLog();
    for (var i = 0; i < 40; i++) {
      log.applyAll([
        const TurnStarted(),
        UserMessage('Contexte $i'),
        AgentMessage('Explication détaillée $i', messageId: 'a$i'),
        const TurnEnded(StopReason.endTurn),
      ]);
    }
    log.applyAll([
      const TurnStarted(),
      const UserMessage('Choisis les tests'),
      FakeSessions.questionMultiple().question!,
    ]);
    Map<String, Object>? sent;
    await tester.pumpWidget(_page(log, ui: MikkyUi.light, answer: (value) => sent = value));
    await tester.pumpAndSettle();
    expect(find.byType(HomeAppTile), findsNothing);
    expect(find.byType(MiniMikky), findsNothing);
    expect(find.text('Codex · Question en attente'), findsOneWidget);
    final header = tester.getRect(find.text('Mikky · Revoir les questions de la notch'));
    final card = tester.widget<QuestionCard>(find.byType(QuestionCard));
    expect(card.scroll!.offset, greaterThan(0));
    await tester.tap(find.text('Unitaires'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contexte'));
    await tester.pumpAndSettle();
    expect(card.scroll!.offset, 0);
    expect(tester.getRect(find.text('Mikky · Revoir les questions de la notch')), header);
    expect(find.text('Contexte 0'), findsOneWidget);
    await tester.tap(find.text('Question'));
    await tester.pumpAndSettle();
    expect(find.text('1 réponse sélectionnée'), findsOneWidget);
    await tester.tap(find.text('Envoyer'));
    expect(sent, {
      'tests': ['Unitaires'],
    });
    expect(tester.takeException(), isNull);
  });

  for (final (label, ui) in [('light', MikkyUi.light), ('dark', MikkyUi.dark)]) {
    testWidgets('conversation series keeps context before the complete question block $label', tags: 'golden', (
      tester,
    ) async {
      await tester.pumpWidget(_page(FakeSessions.questions(), ui: ui));
      await tester.pumpAndSettle();
      final message = tester.getRect(find.text('Prépare le stockage des tâches planifiées.'));
      final steps = tester.getRect(find.byType(StepTabs));
      final question = tester.getRect(find.text('Quelle base de données ?'));
      final choice = tester.getRect(find.text('SQLite'));
      expect(message.bottom, lessThan(steps.top));
      expect(steps.bottom, lessThan(question.top));
      expect(question.bottom, lessThan(choice.top));
      expect(question.top - steps.bottom, lessThan(12));
      expect(find.byType(HomeAppTile), findsNothing);
      await expectLater(
        find.byKey(const Key('question-page')),
        matchesGoldenFile('goldens/question_conversation_series_$label.png'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('conversation question $label', tags: 'golden', (tester) async {
      await tester.pumpWidget(_page(FakeSessions.questionMultiple(), ui: ui, answer: (_) {}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unitaires'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('question-page')),
        matchesGoldenFile('goldens/question_conversation_$label.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
