import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_notch_requests.dart';
import 'package:mikky/boards/boards_app.dart';
import 'package:mikky/boards/canvas.dart';
import 'package:mikky/boards/fake_sessions.dart';
import 'package:mikky/home/home_app.dart';
import 'package:mikky/home/home_app_tile.dart';
import 'package:mikky/home/home_layout.dart';
import 'package:mikky/home/home_view.dart';
import 'package:mikky/home/notch_request.dart';
import 'package:mikky/side/home_screen.dart';
import 'package:mikky/side/question_card.dart';
import 'package:mikky/ui/brand/app_tile.dart';
import 'package:mikky/ui/content/cards.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'load_fonts.dart';

SessionLog permission(Object id) => SessionLog()
  ..applyAll([
    const SessionStarted('test'),
    const TurnStarted(),
    PermissionAsked(
      id,
      toolCallId: 'test',
      title: 'flutter test',
      options: const [PermissionOption('yes', 'Oui', 'allow_once'), PermissionOption('no', 'Non', 'reject_once')],
    ),
  ]);

SessionLog question({Object id = 'q', bool multiple = false}) => SessionLog()
  ..applyAll([
    const SessionStarted('test'),
    const TurnStarted(),
    QuestionAsked(
      id,
      message: 'Quelle base ?',
      questions: [
        Question(
          'db',
          text: 'Quelle base ?',
          multiple: multiple,
          otherKey: 'other',
          choices: const [QuestionChoice('SQLite'), QuestionChoice('Postgres')],
        ),
      ],
    ),
  ]);

AgentEntry entry(String id, {SessionLog? log}) =>
    AgentEntry(id, AgentProvider.claude, AgentHost.windows, AgentOrigin.external, r'C:\test', DateTime.now())
      ..storedTitle = id
      ..failure = log ?? (SessionLog()..apply(const TurnStarted()))
      ..status = log?.statusAt(DateTime.now()) ?? AgentStatus.working;

Widget host(Widget child, {MikkyUi ui = MikkyUi.light}) => WidgetsApp(
  color: const Color(0xffffffff),
  builder: (context, _) => MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: MikkyUiScope(
      ui: ui,
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);
  final frame = find.byType(NotchRequest);

  for (final answer in [AgentAnswer.allow, AgentAnswer.deny]) {
    testWidgets('notch sends $answer to the waiting agent and keeps the app tiles', (tester) async {
      final waiting = entry('Feu vert', log: permission('p'));
      final entries = [waiting, for (var i = 0; i < 4; i++) entry('Agent $i')];
      final sent = <(String, AgentAnswer)>[];
      late StateSetter rebuild;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, set) {
              rebuild = set;
              return HomeScreen(
                layout: HomeLayout.top,
                entries: entries,
                open: (_) {},
                canLaunch: false,
                canAnswer: (_) => true,
                answer: (id, a) {
                  sent.add((id, a));
                  waiting.log.apply(PermissionAnswered('p', allowed: a == AgentAnswer.allow));
                  waiting.status = AgentStatus.working;
                  rebuild(() {});
                },
              );
            },
          ),
        ),
      );
      expect(tester.getSize(find.byType(HomeView)), const Size(700, 200));
      expect(find.byType(HomeAppTile), findsNWidgets(4));
      expect(tester.getSize(find.byType(AppTile).first), const Size(160, 42));
      expect(find.text('1 demande'), findsNothing);
      await tester.tap(find.text(answer == AgentAnswer.allow ? 'Oui' : 'Non'));
      await tester.pumpAndSettle();
      expect(sent, [('Feu vert', answer)]);
      expect(frame, findsNothing);
      expect(waiting.log.pending, isEmpty);
      expect(tester.getSize(find.byType(AppTile).first), const Size(160, 42));
    });
  }

  testWidgets('later sends nothing, another request remains usable, and the old one reopens', (tester) async {
    final first = entry('Première', log: permission('one'));
    final second = entry('Deuxième', log: permission('two'));
    final sent = <String>[];
    await tester.pumpWidget(
      host(
        HomeScreen(
          layout: HomeLayout.top,
          entries: [first, second, entry('Au travail')],
          canLaunch: false,
          open: sent.add,
          canAnswer: (_) => true,
          answer: (id, _) => sent.add(id),
        ),
      ),
    );
    expect(tester.widget<NotchRequest>(frame).name, 'Première');
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(first.log.pending, hasLength(1));
    expect(tester.widget<NotchRequest>(frame).name, 'Deuxième');
    await tester.tap(find.byKey(const ValueKey('Première')));
    await tester.pumpAndSettle();
    expect(tester.widget<NotchRequest>(frame).name, 'Première');
    await tester.tap(find.byKey(const ValueKey('Au travail')));
    expect(sent, ['Au travail']);
  });

  testWidgets('a new request replaces a deferred one and a stale callback cannot answer it', (tester) async {
    final waiting = entry('Agent', log: permission('old'));
    final sent = <AgentAnswer>[];
    late StateSetter refresh;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (_, set) {
            refresh = set;
            return HomeScreen(
              layout: HomeLayout.top,
              entries: [waiting],
              open: (_) {},
              canAnswer: (_) => true,
              answer: (_, a) => sent.add(a),
            );
          },
        ),
      ),
    );
    final oldAnswer = tester.widget<NotchRequest>(frame).onAnswer!;
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(frame, findsNothing);
    waiting.failure = permission('new');
    oldAnswer(AgentAnswer.allow);
    expect(sent, isEmpty);
    refresh(() {});
    await tester.pumpAndSettle();
    expect(frame, findsOneWidget);
  });

  testWidgets('read-only permissions only offer later or the source application', (tester) async {
    var revealed = 0;
    await tester.pumpWidget(
      host(
        HomeScreen(
          layout: HomeLayout.top,
          entries: [entry('Observée', log: permission('p'))],
          open: (_) {},
          reveal: (_) => revealed++,
        ),
      ),
    );
    expect(find.text('Oui'), findsNothing);
    expect(find.text('Non'), findsNothing);
    await tester.tap(find.text('Ouvrir l’app'));
    expect(revealed, 1);
  });

  testWidgets('replacing an agent entry invalidates its previous answer callback', (tester) async {
    final sent = <AgentAnswer>[];
    Future<void> show(AgentEntry waiting) => tester.pumpWidget(
      host(
        HomeScreen(
          layout: HomeLayout.top,
          entries: [waiting],
          open: (_) {},
          canAnswer: (_) => true,
          answer: (_, a) => sent.add(a),
        ),
      ),
    );
    await show(entry('Agent', log: permission('old')));
    final oldAnswer = tester.widget<NotchRequest>(frame).onAnswer!;
    await show(entry('Agent', log: permission('new')));
    oldAnswer(AgentAnswer.allow);
    expect(sent, isEmpty);
    tester.widget<NotchRequest>(frame).onAnswer!(AgentAnswer.deny);
    expect(sent, [AgentAnswer.deny]);
  });

  testWidgets('the shared question answers by keyboard with two unchanged tiles beside it', (tester) async {
    final sent = <Map<String, Object>?>[];
    await tester.pumpWidget(
      host(
        HomeScreen(
          layout: HomeLayout.top,
          canLaunch: false,
          entries: [
            entry('Base', log: question()),
            entry('A'),
            entry('B'),
            entry('C'),
          ],
          open: (_) {},
          canAnswerQuestion: (_) => true,
          answerQuestion: (_, a) => sent.add(a),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(QuestionCard), findsOneWidget);
    expect(find.byType(HomeAppTile), findsNWidgets(2));
    expect(tester.getSize(find.byType(AppTile).first), const Size(160, 42));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    expect(sent, [
      {'db': 'Postgres'},
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('question later does not skip or send the form', (tester) async {
    final sent = <Map<String, Object>?>[];
    final log = question();
    await tester.pumpWidget(
      host(
        HomeScreen(
          layout: HomeLayout.top,
          entries: [entry('Base', log: log)],
          open: (_) {},
          canAnswerQuestion: (_) => true,
          answerQuestion: (_, a) => sent.add(a),
        ),
      ),
    );
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(log.question, isNotNull);
    expect(frame, findsNothing);
  });

  testWidgets('typing in Other never triggers request shortcuts', (tester) async {
    final sent = <Map<String, Object>?>[];
    var later = 0;
    await tester.pumpWidget(
      host(
        HomeView(
          animate: false,
          request: NotchRequest(
            name: 'Base',
            log: question(),
            onAnswerQuestion: sent.add,
            onOpen: () {},
            onLater: () => later++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Autre…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'postgres');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(later, 0);
    expect(sent, isEmpty);
  });

  testWidgets('a question series keeps previous and next answers inside the notch', (tester) async {
    final sent = <Map<String, Object>?>[];
    await tester.pumpWidget(
      host(
        HomeView(
          animate: false,
          request: NotchRequest(
            name: 'Stockage',
            log: FakeSessions.questions(),
            onAnswerQuestion: sent.add,
            onOpen: () {},
            onLater: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(sent, [
      {'db': 'SQLite', 'when': 'À l’heure dite', 'log': 'Oui'},
    ]);
  });

  testWidgets('modified keys do not approve, deny or defer a request', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        HomeView(
          animate: false,
          request: NotchRequest(
            name: 'Tests',
            log: permission('p'),
            onAnswer: (_) => calls++,
            onOpen: () {},
            onLater: () => calls++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    for (final key in [LogicalKeyboardKey.keyO, LogicalKeyboardKey.keyN, LogicalKeyboardKey.keyP]) {
      await tester.sendKeyEvent(key);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(calls, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    expect(calls, 1);
  });

  testWidgets('the right home keeps its existing request navigation', (tester) async {
    var opened = '';
    await tester.pumpWidget(
      host(
        HomeScreen(
          entries: [entry('Agent', log: permission('p'))],
          open: (id) => opened = id,
        ),
      ),
    );
    expect(frame, findsNothing);
    tester.widget<HomeView>(find.byType(HomeView)).onOpen!(const HomeApp(id: 'Agent', name: 'Agent'));
    expect(opened, 'Agent');
  });

  testWidgets('long commands scroll in full while compact answers stay visible', (tester) async {
    final command = [for (var i = 0; i < 40; i++) 'step $i'].join('\n');
    final log = permission('long')..apply(PermissionAsked('long', toolCallId: 'test', title: command));
    await tester.pumpWidget(
      host(
        HomeView(
          animate: false,
          request: NotchRequest(name: 'Commande longue', log: log, onOpen: () {}, onLater: () {}, onAnswer: (_) {}),
        ),
      ),
    );
    expect(tester.getSize(frame).height, HomeLayout.taskHeight);
    expect(tester.getSize(find.byType(AnswerBar)).height, 24);
    expect(tester.widget<CodePill>(find.byType(CodePill)).maxLines, isNull);
    expect(tester.widget<CodePill>(find.byType(CodePill)).code, command);
    final yes = tester.getRect(find.text('Oui'));
    await tester.drag(find.descendant(of: frame, matching: find.byType(SingleChildScrollView)), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Oui')), yes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long question tabs wrap within the notch and actions keep their room', (tester) async {
    final log = SessionLog()
      ..apply(
        QuestionAsked(
          'long',
          message: '',
          questions: [
            for (var i = 0; i < 6; i++)
              Question(
                'q$i',
                title: 'Configuration du stockage numéro $i',
                text: 'Quelle base ?',
                choices: const [QuestionChoice('SQLite'), QuestionChoice('Postgres')],
              ),
          ],
        ),
      );
    await tester.pumpWidget(
      host(
        HomeView(
          animate: false,
          request: NotchRequest(
            name: 'Configuration',
            log: log,
            onOpen: () {},
            onLater: () {},
            onAnswerQuestion: (_) {},
          ),
        ),
      ),
    );
    expect(tester.getSize(frame).height, HomeLayout.taskHeight);
    expect(tester.getRect(find.text('Plus tard')).bottom, lessThanOrEqualTo(tester.getRect(frame).bottom));
    expect(tester.takeException(), isNull);
  });

  for (final (label, ui) in [('light', MikkyUi.light), ('dark', MikkyUi.dark)]) {
    testWidgets('notch requests inherit the $label theme', (tester) async {
      await tester.pumpWidget(
        host(
          HomeView(
            animate: false,
            request: NotchRequest(
              name: 'Tests',
              log: permission('theme'),
              onOpen: () {},
              onLater: () {},
              onAnswer: (_) {},
            ),
          ),
          ui: ui,
        ),
      );
      expect(MikkyUi.of(tester.element(find.byType(CodePill))), same(ui));
      expect(tester.takeException(), isNull);
    });

    testWidgets('flat notch requests $label', tags: 'golden', (tester) async {
      final spec = BoardSpec('Demandes dans le notch', '', (_) => [inlineRequestSection()]);
      const boundary = Key('request-board');
      Widget page() => MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: 0,
            maxHeight: double.infinity,
            child: RepaintBoundary(
              key: boundary,
              child: BoardBand(spec: spec, ui: ui),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.binding.setSurfaceSize(tester.getSize(find.byKey(boundary)));
      tester.view.devicePixelRatio = 1;
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(page());
      await tester.pump(const Duration(milliseconds: 500));
      await expectLater(find.byKey(boundary), matchesGoldenFile('goldens/boards/notch_requests_$label.png'));
    });
  }
}
