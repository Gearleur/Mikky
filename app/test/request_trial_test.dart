import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/side/question_card.dart';
import 'package:mikky/side/request_keys.dart';
import 'package:mikky/ui/content/diff_view.dart';
import 'package:mikky/ui/controls/step_tabs.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'load_fonts.dart';

QuestionAsked _ask(List<Question> questions, {Object id = 1}) =>
    QuestionAsked(id, message: questions.first.text, questions: questions);

const _db = Question(
  'db',
  text: 'Quelle base ?',
  otherKey: 'db_other',
  choices: [QuestionChoice('SQLite'), QuestionChoice('Postgres')],
);
const _tests = Question(
  'tests',
  text: 'Quels tests ?',
  multiple: true,
  choices: [QuestionChoice('Unitaires'), QuestionChoice('Bout en bout')],
);

Future<void> _pump(WidgetTester tester, Widget child, {RequestKeys? keys}) async {
  tester.view.physicalSize = const Size(700, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget body = MikkyUiScope(ui: MikkyUi.light, child: child);
  if (keys != null) body = RequestKeysScope(keys: keys, child: body);
  await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: body));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('one choice answers at once', (tester) async {
    Map<String, Object>? got;
    await _pump(tester, QuestionCard(question: _ask([_db]), onAnswer: (a) => got = a));
    await tester.tap(find.text('Postgres'));
    expect(got, {'db': 'Postgres'});
  });

  testWidgets('read only: a choice leads where it is answered, « Autre… » is gone', (tester) async {
    var there = 0;
    await _pump(
      tester,
      QuestionCard(
        question: _ask([_db]),
        onAnswer: null,
        elsewhere: [('Répondre dans Claude', () => there++)],
        onElsewhere: () => there++,
      ),
    );
    expect(find.text('Autre…'), findsNothing);
    expect(find.text('Passer'), findsNothing);
    await tester.tap(find.text('Postgres'));
    await tester.tap(find.text('Répondre dans Claude'));
    expect(there, 2);
  });

  testWidgets('several choices: ticked, then sent; nothing ticked, nothing to send', (tester) async {
    Map<String, Object>? got;
    await _pump(tester, QuestionCard(question: _ask([_tests]), onAnswer: (a) => got = a));
    await tester.tap(find.text('Envoyer'));
    expect(got, isNull);
    await tester.tap(find.text('Unitaires'));
    await tester.tap(find.text('Bout en bout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer'));
    expect(got, {
      'tests': ['Unitaires', 'Bout en bout'],
    });
  });

  testWidgets('several questions, one at a time; « Autre… » sends what is written', (tester) async {
    Map<String, Object>? got;
    await _pump(tester, QuestionCard(question: _ask([_tests, _db]), onAnswer: (a) => got = a));
    expect(find.text('Quels tests ?'), findsOneWidget);
    await tester.tap(find.text('Unitaires'));
    await tester.pumpAndSettle();
    // Another question left: « Suivante », not « Envoyer ».
    expect(find.text('Envoyer'), findsNothing);
    await tester.tap(find.text('Suivante'));
    await tester.pumpAndSettle();
    expect(find.text('Quelle base ?'), findsOneWidget);
    expect(got, isNull);
    await tester.tap(find.text('Autre…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'DuckDB');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer'));
    expect(got, {
      'tests': ['Unitaires'],
      'db_other': 'DuckDB',
    });
  });

  testWidgets('« Autre… » closes on a second click, and what was written goes', (tester) async {
    Map<String, Object>? got;
    await _pump(tester, QuestionCard(question: _ask([_db]), onAnswer: (a) => got = a));
    await tester.tap(find.text('Autre…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'DuckDB');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autre…'));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('Envoyer'), findsNothing);
    await tester.tap(find.text('Autre…'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
    await tester.tap(find.text('Postgres'));
    expect(got, {'db': 'Postgres'});
  });

  testWidgets('an answered question opens again from its mark, with its answer; then the first one left', (
    tester,
  ) async {
    Map<String, Object>? got;
    const when = Question('when', text: 'Quand ?', choices: [QuestionChoice('Maintenant'), QuestionChoice('Demain')]);
    await _pump(tester, QuestionCard(question: _ask([_db, when, _tests]), onAnswer: (a) => got = a));
    await tester.tap(find.text('SQLite'));
    await tester.pumpAndSettle();
    expect(find.text('Quand ?'), findsOneWidget);
    // The first mark: the question answered.
    await tester.tapAt(tester.getTopLeft(find.byType(StepMark).first) + const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Quelle base ?'), findsOneWidget);
    await tester.tap(find.text('Postgres'));
    await tester.pumpAndSettle();
    expect(find.text('Quand ?'), findsOneWidget);
    expect(got, isNull);
    await tester.tap(find.text('Demain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unitaires'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer'));
    expect(got, {
      'db': 'Postgres',
      'when': 'Demain',
      'tests': ['Unitaires'],
    });
  });

  testWidgets('« Précédente » opens the one before with its answer, « Suivante » keeps it', (tester) async {
    Map<String, Object>? got;
    const when = Question('when', text: 'Quand ?', choices: [QuestionChoice('Maintenant'), QuestionChoice('Demain')]);
    await _pump(tester, QuestionCard(question: _ask([_db, when]), onAnswer: (a) => got = a));
    expect(find.text('Précédente'), findsNothing);
    await tester.tap(find.text('SQLite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Précédente'));
    await tester.pumpAndSettle();
    expect(find.text('Quelle base ?'), findsOneWidget);
    await tester.tap(find.text('Suivante'));
    await tester.pumpAndSettle();
    expect(find.text('Quand ?'), findsOneWidget);
    await tester.tap(find.text('Maintenant'));
    expect(got, {'db': 'SQLite', 'when': 'Maintenant'});
  });

  testWidgets('« Passer » skips the whole form', (tester) async {
    var skipped = false;
    await _pump(tester, QuestionCard(question: _ask([_db]), onAnswer: (a) => skipped = a == null));
    await tester.tap(find.text('Passer'));
    expect(skipped, isTrue);
  });

  testWidgets('the island\'s keys: 1 to 4 pick, Entrée sends, a key it has no use for is left', (tester) async {
    final keys = RequestKeys();
    Map<String, Object>? got;
    await _pump(
      tester,
      QuestionCard(question: _ask([_tests]), onAnswer: (a) => got = a),
      keys: keys,
    );
    expect(keys.send(RequestKey.choice4), isFalse);
    expect(keys.send(RequestKey.enter), isFalse, reason: 'nothing ticked yet');
    expect(keys.send(RequestKey.choice2), isTrue);
    await tester.pumpAndSettle();
    expect(keys.send(RequestKey.enter), isTrue);
    expect(got, {
      'tests': ['Bout en bout'],
    });
  });

  testWidgets('the same request rebuilt keeps what is being answered', (tester) async {
    Map<String, Object>? got;
    Widget card(QuestionAsked q) => QuestionCard(question: q, onAnswer: (a) => got = a);
    await _pump(tester, card(_ask([_tests])));
    await tester.tap(find.text('Unitaires'));
    await tester.pumpAndSettle();
    // Equal, not identical: the same request.
    await _pump(tester, card(_ask([_tests])));
    await tester.tap(find.text('Envoyer'));
    expect(got, {
      'tests': ['Unitaires'],
    });
  });

  testWidgets('a diff numbers its lines as in the file; an excerpt, not at all', (tester) async {
    Future<void> show(FileDiff change) => _pump(tester, DiffPage(path: change.path, changes: [change], back: () {}));
    await show(const FileDiff(r'C:\p\a.txt', 'one\ntwo\nthree', 'one\n2\nthree', line: 40));
    for (final n in ['40', '41', '42']) {
      expect(find.text(n), findsWidgets);
    }
    await show(const FileDiff(r'C:\p\a.txt', 'one\ntwo', 'one\n2'));
    expect(find.text('1'), findsNothing);
  });

  testWidgets('a folded run of unchanged lines opens on a click', (tester) async {
    final before = [for (var i = 0; i < 30; i++) 'line $i'].join('\n');
    final after = before.replaceFirst('line 0', 'line zero').replaceFirst('line 29', 'line twenty-nine');
    await _pump(tester, DiffPage(path: r'C:\p\a.txt', changes: [FileDiff(r'C:\p\a.txt', before, after)], back: () {}));
    expect(find.text('line 15'), findsNothing);
    await tester.tap(find.textContaining('lignes inchangées'));
    await tester.pumpAndSettle();
    expect(find.text('line 15'), findsOneWidget);
  });
}
