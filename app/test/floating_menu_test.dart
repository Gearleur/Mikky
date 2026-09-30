import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/overlay/overlay_channel.dart';
import 'package:mikky/ui/floating_menu.dart';
import 'package:mikky/ui/tokens.dart';

import 'load_fonts.dart';

/// Our floating menu: the button grows into it where the mouse was
/// pressed, inside the small window; a choice, Échap or a click outside
/// shrink it back.
void main() {
  setUpAll(loadAppFonts);

  const entries = [MenuEntry(1, 'Renommer…'), MenuEntry.separator(), MenuEntry(2, 'Supprimer…', checked: true)];

  Future<Future<int?> Function()> pumpWindow(WidgetTester tester) async {
    FloatingMenu.track();
    late BuildContext window;
    await tester.pumpWidget(MikkyUiTheme(
      ui: MikkyUi.light,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(initialEntries: [
          OverlayEntry(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                height: 600,
                child: Builder(builder: (context) {
                  window = context;
                  return const SizedBox.expand(key: Key('window'));
                }),
              ),
            ),
          ),
        ]),
      ),
    ));
    return () => showFloatingMenu(window, entries);
  }

  testWidgets('a choice comes back, the menu goes', (tester) async {
    final open = await pumpWindow(tester);
    await tester.tapAt(const Offset(320, 40));
    final chosen = open();
    await tester.pumpAndSettle();
    expect(find.text('Renommer…'), findsOneWidget);
    // Grown out of the button around the press, inside the window.
    final item = tester.getRect(find.text('Renommer…'));
    expect(item.right, lessThanOrEqualTo(360));
    expect(item.top, greaterThan(20));
    expect(item.left, lessThan(320));
    await tester.tap(find.text('Supprimer…'));
    await tester.pumpAndSettle();
    expect(await chosen, 2);
    expect(find.text('Renommer…'), findsNothing);
  });

  testWidgets('Échap or a click outside: nothing chosen', (tester) async {
    final open = await pumpWindow(tester);
    var chosen = open();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await chosen, isNull);
    chosen = open();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 560));
    await tester.pumpAndSettle();
    expect(await chosen, isNull);
    expect(find.text('Renommer…'), findsNothing);
  });
}
