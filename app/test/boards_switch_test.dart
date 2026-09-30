import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/boards_app.dart';

import 'load_fonts.dart';

/// A click in the sidebar: the white square slides at once, the board
/// follows once it has arrived (building a board would make it jump).
void main() {
  setUpAll(loadAppFonts);

  testWidgets('the board follows the square', (tester) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Directionality(textDirection: TextDirection.ltr, child: Boards()),
    ));
    // The band's title: the board shown.
    Finder title(String name) => find.byWidgetPredicate((w) => w is Text && w.data == name && (w.style?.fontSize ?? 0) == 30);
    expect(title('Marque'), findsWidgets);
    await tester.tap(find.text('Accueil').first);
    await tester.pump();
    expect(title('Marque'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 300));
    expect(title('Accueil'), findsWidgets);
    expect(title('Marque'), findsNothing);
  });
}
