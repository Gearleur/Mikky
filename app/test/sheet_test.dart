import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_home.dart';
import 'package:mikky/home/history_sheet.dart';
import 'package:mikky/ui/sheet.dart';
import 'package:mikky/ui/tokens.dart';

import 'load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the history button opens the sheet over the home; the dark, × or Échap close it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 600));
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MikkyUiTheme(ui: MikkyUi.light, child: Align(alignment: Alignment.topLeft, child: HistoryTry())),
      ),
    ));
    expect(find.byType(HistoryList), findsNothing);
    Future<void> open() async {
      await tester.tap(find.bySemanticsLabel('Historique'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryList), findsOneWidget);
      expect(find.text('Traduis le README'), findsOneWidget);
    }

    await open();
    await tester.tap(find.bySemanticsLabel('Fermer'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryList), findsNothing);

    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(HistoryList), findsNothing);

    // A click on the darkened home, above the sheet.
    await open();
    final panel = tester.getRect(find.byType(SheetPanel));
    await tester.tapAt(Offset(panel.center.dx, panel.top - 8));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryList), findsNothing);

    // A row closes it too (and would open the agent).
    await open();
    await tester.tap(find.text('Traduis le README'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryList), findsNothing);
  });
}
