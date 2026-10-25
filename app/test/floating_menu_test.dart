import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/overlay/overlay_channel.dart';
import 'package:mikky/settings/settings_button.dart';
import 'package:mikky/ui/controls/buttons.dart';
import 'package:mikky/ui/foundation/icons.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky/ui/overlays/floating_menu.dart';
import 'package:mikky/ui/pixels/pixel_fx.dart';

import 'load_fonts.dart';

/// Our floating menu: the button grows into it where the mouse was
/// pressed, inside the small window; a choice, Échap or a click outside
/// shrink it back.
void main() {
  setUpAll(loadAppFonts);

  const entries = [MenuEntry(1, 'Renommer…'), MenuEntry.separator(), MenuEntry(2, 'Supprimer…', checked: true)];

  Future<Future<int?> Function()> pumpWindow(
    WidgetTester tester, {
    bool button = false,
    Size size = const Size(360, 600),
    List<MenuEntry> menuEntries = entries,
    double buttonRight = 14,
  }) async {
    FloatingMenu.track();
    late BuildContext window;
    await tester.pumpWidget(
      MikkyUiTheme(
        ui: MikkyUi.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Builder(
                      builder: (context) {
                        window = context;
                        return Stack(
                          children: [
                            const SizedBox.expand(key: Key('window')),
                            if (button)
                              Positioned(
                                top: 14,
                                right: buttonRight,
                                child: RoundButton.menu(onPressed: () => showFloatingMenu(context, menuEntries)),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return () => showFloatingMenu(window, menuEntries);
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
    final second = showFloatingMenu(tester.element(find.byKey(const Key('window'))), const [
      MenuEntry(10, 'Oui, supprimer'),
      MenuEntry(12, 'Annuler'),
    ]);
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
      if (stars.isNotEmpty && find.text('Renommer…').evaluate().isEmpty) {
        expect((stars.single - resting).distance, lessThan(1));
      }
    }
    await tester.pumpAndSettle();
    expect(shown(), [resting]);
  });
  testWidgets('long action menu fits the top notch and scrolls to the last action', (tester) async {
    await pumpWindow(
      tester,
      button: true,
      size: const Size(700, 200),
      menuEntries: [for (var i = 1; i <= 12; i++) MenuEntry(i, 'Action $i')],
    );
    await tester.tap(find.byType(RoundButton));
    await tester.pumpAndSettle();
    final scroll = find.byType(SingleChildScrollView);
    final rect = tester.getRect(scroll);
    expect(rect.top, greaterThanOrEqualTo(8));
    expect(rect.bottom, lessThanOrEqualTo(192));
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(692));
    await tester.drag(scroll, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Action 12').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Action 12'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a clamped menu keeps its star centered on the original button', (tester) async {
    await pumpWindow(tester, button: true, buttonRight: 312);
    final resting = tester.getCenter(find.byType(PixelStar));
    await tester.tapAt(resting);
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      for (final element in find.byType(PixelStar).evaluate()) {
        if (element.debugGetDiagnosticChain().any((a) => a.widget is Opacity && (a.widget as Opacity).opacity < .01)) {
          continue;
        }
        final box = element.findRenderObject()! as RenderBox;
        expect((box.localToGlobal(box.size.center(Offset.zero)) - resting).distance, lessThan(.1));
      }
    }
    FloatingMenu.dismissAll();
    await tester.pumpAndSettle();
  });

  testWidgets('the history action menu fits without scrolling and stays inside the notch while moving', (tester) async {
    await pumpWindow(
      tester,
      button: true,
      size: const Size(700, 200),
      menuEntries: const [
        MenuEntry(1, 'Ouvrir dans VS Code', icon: 'code'),
        MenuEntry(2, 'Ouvrir le dossier', icon: 'folder'),
        MenuEntry.separator(),
        MenuEntry(3, 'Renommer…', icon: 'edit'),
        MenuEntry(4, 'Épingler', icon: 'pin'),
        MenuEntry(5, 'Archiver', icon: 'archive'),
        MenuEntry.separator(),
        MenuEntry(6, 'Supprimer…', icon: 'trash'),
      ],
    );
    final star = find.byType(PixelStar);
    final origin = tester.getRect(star);
    final press = await tester.startGesture(origin.center);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getRect(star), origin);
    await press.up();
    await tester.pump();
    await tester.pump();
    // Let the initial focus notification settle before tracking rebuilds.
    await tester.pump(const Duration(milliseconds: 16));
    final labels = ['Ouvrir dans VS Code', 'Ouvrir le dossier', 'Renommer…', 'Épingler', 'Archiver', 'Supprimer…'];
    final openingText = {for (final label in labels) label: tester.widget<Text>(find.text(label))};
    void checkFrame() {
      final clips = find.byType(ClipRRect);
      if (clips.evaluate().isEmpty) return;
      final panel = tester.getRect(clips);
      expect(panel.left, greaterThanOrEqualTo(12));
      expect(panel.top, greaterThanOrEqualTo(12));
      expect(panel.right, lessThanOrEqualTo(688));
      expect(panel.bottom, lessThanOrEqualTo(188));
    }

    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      checkFrame();
      // Moving the frame must reuse the laid-out labels, rather than
      // rebuilding every menu item throughout the animation.
      for (final label in labels) {
        expect(
          identical(tester.widget<Text>(find.text(label)), openingText[label]),
          isTrue,
          reason: '$label, frame $i',
        );
      }
    }
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, 0);
    expect(tester.getSize(find.byType(ClipRRect)).width, lessThan(220));
    expect(tester.getRect(find.byType(ClipRRect)).top, 12);
    expect(tester.getRect(find.byType(ClipRRect)).bottom, 188);
    expect(find.text('Supprimer…').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      checkFrame();
    }
    await tester.pumpAndSettle();
    expect(tester.getRect(star), origin);
    expect(tester.takeException(), isNull);
  });

  for (final ui in [MikkyUi.light, MikkyUi.dark]) {
    testWidgets('settings and history hover is subtle and steady in ${ui.isLight ? 'light' : 'dark'} mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MikkyUiTheme(
          ui: ui,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsButton(onPressed: () {}),
                  RoundButton('history', ghost: true, size: 24, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final icon in ['sliders', 'history']) {
        final button = find.byWidgetPredicate((w) => w is RoundButton && w.icon == icon);
        final bounds = tester.getRect(button);
        await mouse.moveTo(bounds.center);
        await tester.pumpAndSettle();
        final hover = tester.widget<AnimatedContainer>(
          find.descendant(of: button, matching: find.byType(AnimatedContainer)),
        );
        final color = (hover.decoration! as BoxDecoration).color!;
        expect(color.a, inInclusiveRange(.09, .14));
        expect(tester.widget<MikkyIcon>(find.descendant(of: button, matching: find.byType(MikkyIcon))).color, ui.text);
        expect(tester.getRect(button), bounds);
        await mouse.down(bounds.center);
        await tester.pump(const Duration(milliseconds: 80));
        // Hover belongs to the fixed hit area, even while its child shrinks.
        await mouse.moveTo(bounds.topLeft + const Offset(.5, .5));
        await tester.pumpAndSettle();
        final held = tester.widget<AnimatedContainer>(
          find.descendant(of: button, matching: find.byType(AnimatedContainer)),
        );
        expect((held.decoration! as BoxDecoration).color!.a, greaterThan(.05));
        await mouse.up();
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        final idle = tester.widget<AnimatedContainer>(
          find.descendant(of: button, matching: find.byType(AnimatedContainer)),
        );
        expect((idle.decoration! as BoxDecoration).color!.a, 0);
      }
      await mouse.removePointer();
    });
  }
}
