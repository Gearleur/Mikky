import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_components_history.dart';
import 'package:mikky/boards/board_home.dart';
import 'package:mikky/boards/board_notch.dart';
import 'package:mikky/home/history_sheet.dart';
import 'package:mikky/home/home_frame.dart';
import 'package:mikky/home/home_layout.dart';
import 'package:mikky/home/home_view.dart';
import 'package:mikky/ui/content/history_view.dart';
import 'package:mikky/ui/controls/page_dots.dart';
import 'package:mikky/ui/foundation/tokens.dart';

import 'load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('shared history opens over the home; back, backdrop and Échap close it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 600));
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiTheme(
            ui: MikkyUi.light,
            child: Align(alignment: Alignment.topLeft, child: _HistoryHost()),
          ),
        ),
      ),
    );
    expect(find.byType(HistoryView), findsNothing);
    Future<void> open() async {
      await tester.tap(find.bySemanticsLabel('Historique'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryView), findsOneWidget);
      expect(find.text('Traduis le README'), findsOneWidget);
    }

    await open();
    await tester.tap(find.bySemanticsLabel('Retour à l’accueil'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryView), findsNothing);

    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(HistoryView), findsNothing);

    // A click on the darkened home, above the sheet.
    await open();
    final panel = tester.getRect(find.byKey(const ValueKey('history-top-list')));
    await tester.tapAt(Offset(panel.center.dx, panel.top - 8));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryView), findsNothing);

    // The search looks in the titles.
    await open();
    await tester.tap(find.bySemanticsLabel('Rechercher dans l’historique'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'readme');
    await tester.pump();
    expect(find.text('Traduis le README'), findsOneWidget);
    expect(find.text('Corrige le hook souris'), findsNothing);
    await tester.enterText(find.byType(EditableText), 'zzz');
    await tester.pump();
    expect(find.text('Rien trouvé'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Retour à l’historique'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Retour à l’accueil'));
    await tester.pumpAndSettle();

    // A row closes it too (and would open the agent).
    await open();
    await tester.tap(find.text('Traduis le README'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryView), findsNothing);
  });

  testWidgets('top history uses one column, four full rows and a detached rail', (tester) async {
    await tester.binding.setSurfaceSize(const Size(840, 320));
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiTheme(
            ui: MikkyUi.light,
            child: Align(
              alignment: Alignment.topLeft,
              child: _HistoryHost(layout: HomeLayout.top),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Historique'));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byKey(const ValueKey('history-top-list')));
    final navigation = tester.getRect(find.byKey(const ValueKey('history-navigation')));
    expect(panel.height, HomeLayout.top.size.height - 2 * HistoryView.inset);
    expect(panel.left - navigation.right, 12);
    expect(tester.widget<HistoryView>(find.byType(HistoryView)).columns, 1);
    expect(tester.getSize(find.byType(SingleChildScrollView)).height, 4 * HistoryView.rowHeight);
    expect(panel.center.dy, closeTo(HomeLayout.top.size.height / 2, .5));
    expect(tester.widget<PageDots>(find.byType(PageDots)).page, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<PageDots>(find.byType(PageDots)).page, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<PageDots>(find.byType(PageDots)).page, 1);
  });
}

/// The installed sheet remains covered independently of the design boards.
class _HistoryHost extends StatelessWidget {
  const _HistoryHost({this.layout = HomeLayout.right});

  final HomeLayout layout;

  @override
  Widget build(BuildContext context) => HomeFrame(
    layout: layout,
    child: HomeView(
      layout: layout,
      apps: layout.notch ? sampleNotchApps : sampleApps,
      animate: false,
      onNew: () {},
      onHistory: (within) => showHistory(within, rows: historyTopSamples, onMenu: (_, _) {}),
    ),
  );
}
