import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/canvas.dart' show OwnOverlay;
import 'package:mikky/home/history_sheet.dart';
import 'package:mikky/side/home_screen.dart';
import 'package:mikky/ui/brand/brand_logo.dart';
import 'package:mikky/ui/content/history_activity.dart';
import 'package:mikky/ui/content/history_view.dart';
import 'package:mikky/ui/controls/field.dart';
import 'package:mikky/ui/foundation/status.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

void main() {
  test('history includes active, recent, old and archived conversations once', () {
    final now = DateTime(2026, 10, 14, 12);
    AgentEntry entry(String id, AgentStatus status, int minutes) =>
        AgentEntry(
            id,
            AgentProvider.claude,
            AgentHost.windows,
            AgentOrigin.external,
            '/project',
            now.subtract(Duration(minutes: minutes)),
          )
          ..status = status
          ..storedTitle = id;
    final thinking = entry('thinking', AgentStatus.thinking, 1);
    final archived = entry('archived', AgentStatus.finished, 10)..mark = const SessionMark(archived: true);
    final deleted = entry('deleted', AgentStatus.finished, 12)..mark = const SessionMark(forgotten: true);
    final superseded = entry('fork-copy', AgentStatus.finished, 15)..supersededBy = 'thinking';
    final rows = historyRows(
      [
        thinking,
        entry('searching', AgentStatus.searching, 2),
        entry('working', AgentStatus.working, 3),
        entry('finished', AgentStatus.finished, 4),
        entry('old', AgentStatus.finished, 10000),
        archived,
        deleted,
        superseded,
      ],
      now,
      recalled: {'thinking'},
    );
    expect(rows.map((r) => r.id), ['thinking', 'searching', 'working', 'finished', 'archived', 'old']);
    expect(rows.where((r) => r.working).map((r) => r.id), ['thinking', 'searching', 'working']);
  });

  testWidgets('compact history shows a thinking star only on active conversations', (tester) async {
    await tester.pumpWidget(
      _theme(
        const SizedBox(
          width: 700,
          height: 200,
          child: HistoryView(
            rows: [
              HistoryRow(
                id: 'active',
                title: 'Réfléchit',
                brand: Brand.claude,
                when: 'Maintenant',
                status: UiStatus.working,
              ),
              HistoryRow(id: 'done', title: 'Terminée', brand: Brand.codex, when: 'Hier', status: UiStatus.finished),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(HistoryActivity), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Agent en cours de travail')), findsOneWidget);
    expect(find.text('Terminée'), findsOneWidget);
  });

  testWidgets('open history follows work, new conversations and search without reopening', (tester) async {
    final rows = _HistoryRows(const [
      HistoryRow(id: 'a', title: 'Conversation A', brand: Brand.claude, when: 'Maintenant', status: UiStatus.working),
    ]);
    addTearDown(rows.dispose);
    await tester.pumpWidget(
      _theme(
        OwnOverlay(
          child: SizedBox(
            width: 700,
            height: 200,
            child: Builder(
              builder: (context) => GestureDetector(
                onTap: () => showHistory(context, rows: rows.value, updates: rows, readRows: () => rows.value),
                child: const Center(child: Text('Historique')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryActivity), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Rechercher dans l’historique'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Conversation A');
    rows.value = const [
      HistoryRow(id: 'a', title: 'Conversation A', brand: Brand.claude, when: 'Maintenant', status: UiStatus.finished),
      HistoryRow(id: 'b', title: 'Conversation B', brand: Brand.codex, when: 'Maintenant', status: UiStatus.working),
    ];
    await tester.pumpAndSettle();
    expect(find.byType(HistoryActivity), findsNothing);
    expect(find.text('1/2'), findsOneWidget);
    expect(tester.widget<SearchField>(find.byType(SearchField)).controller!.text, 'Conversation A');
    await tester.enterText(find.byType(EditableText), '');
    await tester.pumpAndSettle();
    expect(find.text('Retrouver une conversation'), findsOneWidget);
    expect(find.byType(HistoryActivity), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(rows.observed, isTrue);
    expect(find.text('Conversation B'), findsOneWidget);
    expect(find.byType(HistoryActivity), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(rows.observed, isFalse);
    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
    expect(rows.observed, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(rows.observed, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _HistoryRows extends ValueNotifier<List<HistoryRow>> {
  _HistoryRows(super.value);
  bool get observed => hasListeners;
}

Widget _theme(Widget child) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MikkyUiTheme(
      ui: MikkyUi.light,
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);
