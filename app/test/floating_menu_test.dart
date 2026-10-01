import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/overlay/overlay_channel.dart';
import 'package:mikky/ui/buttons.dart';
import 'package:mikky/ui/floating_menu.dart';
import 'package:mikky/ui/pixel_fx.dart';
import 'package:mikky/ui/tokens.dart';

import 'load_fonts.dart';

/// Our floating menu: the button grows into it where the mouse was
/// pressed, inside the small window; a choice, Échap or a click outside
/// shrink it back.
void main() {
  setUpAll(loadAppFonts);

  const entries = [MenuEntry(1, 'Renommer…'), MenuEntry.separator(), MenuEntry(2, 'Supprimer…', checked: true)];

  Future<Future<int?> Function()> pumpWindow(WidgetTester tester, {bool button = false}) async {
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
                  return Stack(children: [
                    const SizedBox.expand(key: Key('window')),
                    if (button)
                      Positioned(top: 14, right: 14, child: RoundButton.menu(onPressed: () => showFloatingMenu(context, entries))),
                  ]);
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

  testWidgets('the island closing closes its menus at once, nothing chosen', (tester) async {
    await pumpWindow(tester, button: true);
    final star = tester.getCenter(find.byType(PixelStar));
    await tester.tapAt(star);
    await tester.pumpAndSettle();
    expect(find.text('Renommer…'), findsOneWidget);
    FloatingMenu.dismissAll();
    await tester.pump();
    expect(find.text('Renommer…'), findsNothing);
    expect(FloatingMenu.covering.value, isNull);
  });

  testWidgets('a follow-up menu takes the panel over, at once and in place', (tester) async {
    final open = await pumpWindow(tester);
    await tester.tapAt(const Offset(320, 40));
    final first = open();
    await tester.pumpAndSettle();
    final corner = tester.getRect(find.text('Renommer…')).topLeft;
    await tester.tap(find.text('Supprimer…'));
    expect(await first, 2);
    // « Supprimer… » asks again, right away.
    final second = showFloatingMenu(tester.element(find.byKey(const Key('window'))), const [MenuEntry(10, 'Oui, supprimer'), MenuEntry(12, 'Annuler')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Renommer…'), findsNothing);
    expect(find.text('Oui, supprimer'), findsOneWidget);
    await tester.pumpAndSettle();
    // Same place: under the button, not down where the item was.
    expect(tester.getRect(find.text('Oui, supprimer')).topLeft, corner);
    await tester.tap(find.text('Annuler'));
    expect(await second, 12);
    await tester.pumpAndSettle();
    expect(find.text('Oui, supprimer'), findsNothing);
  });

  testWidgets('from the star button: one star only, opening and folding back', (tester) async {
    await pumpWindow(tester, button: true);
    final resting = tester.getCenter(find.byType(PixelStar));

    // The stars that show: not under a transparent Opacity.
    List<Offset> shown() => [
      for (final e in find.byType(PixelStar).evaluate())
        if (!e.debugGetDiagnosticChain().any((a) => a.widget is Opacity && (a.widget as Opacity).opacity < .01))
          tester.getCenter(find.byWidget(e.widget).at(find.byWidget(e.widget).evaluate().toList().indexOf(e))),
    ];

    await tester.tapAt(resting);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(shown().length, lessThanOrEqualTo(1));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final stars = shown();
      expect(stars.length, lessThanOrEqualTo(1));
      // When it shows, the menu's star is where the button's is.
      if (stars.isNotEmpty && find.text('Renommer…').evaluate().isEmpty) expect((stars.single - resting).distance, lessThan(1));
    }
    await tester.pumpAndSettle();
    expect(shown(), [resting]);
  });
}
