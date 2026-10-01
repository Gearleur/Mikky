import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/side/session_cards.dart';
import 'package:mikky/ui/messages.dart';
import 'package:mikky/ui/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// The cards that wait for the user (A7.2): a permission with « Toujours »
/// and a question with choices. Update with `flutter test --update-goldens
/// test/side_cards_test.dart`, then look.
Future<void> _loadFonts() async {
  for (final (family, files) in [
    ('Geist', ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf']),
    ('Geist Mono', ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final (name, ui) in [('light', MikkyUi.light), ('dark', MikkyUi.dark)]) {
    testWidgets('waiting cards, $name', (tester) async {
      const size = Size(340, 640);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final log = SessionLog()
        ..apply(const SessionStarted('s1'))
        ..apply(const TurnStarted())
        ..apply(const ToolCallEvent('t1', kind: ToolKind.execute, title: 'Lancer les tests', command: 'npm test -- --watch=false', status: ToolStatus.pending))
        ..apply(const PermissionAsked(1, toolCallId: 't1', title: 'Terminal', options: [
          PermissionOption('once', 'Allow', 'allow_once'),
          PermissionOption('always', 'Always allow', 'allow_always'),
          PermissionOption('no', 'Reject', 'reject_once'),
        ]));
      const question = QuestionAsked(2, message: 'Quelle base de données ?', questions: [
        Question('question_0', text: 'Quelle base de données ?', choices: [QuestionChoice('SQLite'), QuestionChoice('Postgres'), QuestionChoice('Aucune pour l’instant')]),
      ]);
      const board = Key('board');
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: size, disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiTheme(
            ui: ui,
            child: RepaintBoundary(
              key: board,
              child: ColoredBox(
                color: ui.island,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    AskCard(log: log, onAnswer: (_) {}),
                    const SizedBox(height: 16),
                    QuestionCard(question: question, onAnswer: (_) {}),
                    const SizedBox(height: 16),
                    const ChatMessage(
                      me: false,
                      text: 'C’est fait, voir la [doc](https://docs.flutter.dev). Pour relancer :\n```bash\nflutter test --update-goldens test/side_cards_test.dart\n```\n- **1** fichier modifié',
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      await expectLater(find.byKey(board), matchesGoldenFile('goldens/side_cards_$name.png'));
    });
  }
}
