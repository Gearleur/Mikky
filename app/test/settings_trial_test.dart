import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_settings.dart';
import 'package:mikky/settings.dart';
import 'package:mikky/settings/quick_settings_menu.dart';
import 'package:mikky/settings/settings_controls.dart';
import 'package:mikky/theme.dart';
import 'package:mikky/ui/controls/pixel_slider.dart';
import 'package:mikky/ui/foundation/tokens.dart';

import 'load_fonts.dart';

Widget page(Widget child) => WidgetsApp(
  color: MikkyUi.light.island,
  builder: (_, _) => MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: MikkyUiScope(
      ui: MikkyUi.light,
      child: Center(child: child),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);
  testWidgets('a setting has one accessible name and toggles once with the keyboard', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var changes = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        page(
          SizedBox(
            width: 300,
            child: SettingActivator(
              label: 'Sons',
              toggled: true,
              focusNode: focus,
              onPressed: () => changes++,
              child: const Text('Sons'),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Sons'), findsOneWidget);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(changes, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('quick menu supports submenus, keyboard selection and cancellation', (tester) async {
    final settings = Settings();
    var changes = 0, dismissed = 0;
    await tester.pumpWidget(
      page(
        QuickSettingsMenu(
          settings: settings,
          change: (update) {
            changes++;
            update(settings);
          },
          openSettings: () {},
          closeApp: () {},
          dismiss: () => dismissed++,
          compact: true,
          autofocus: true,
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Automatique'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Automatique'), findsNothing);
    expect(settings.theme, ThemeChoice.auto);
    expect(dismissed, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(settings.theme, ThemeChoice.light);
    expect(changes, 1);
    expect(dismissed, 1);
  });

  testWidgets('page and right-click share sound state and preserve volume while muted', (tester) async {
    await tester.pumpWidget(page(const SettingsTrial()));
    final slider = find.byType(PixelSlider);
    expect(tester.widget<PixelSlider>(slider).onChanged, isNotNull);
    await tester.tapAt(tester.getCenter(find.text('Apparence')), buttons: kSecondaryMouseButton);
    await tester.pump();
    await tester.tap(find.text('Sons'));
    await tester.pump();
    expect(tester.widget<PixelSlider>(slider).onChanged, isNull);
    expect(tester.widget<PixelSlider>(slider).value, .5);
    await tester.ensureVisible(find.text('Sons de Mikky'));
    await tester.tap(find.text('Sons de Mikky'));
    await tester.pump();
    expect(tester.widget<PixelSlider>(slider).onChanged, isNotNull);
    expect(tester.widget<PixelSlider>(slider).value, .5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings can be reached by shortcut and Escape returns home', (tester) async {
    await tester.pumpWidget(page(const SettingsTrial(home: true)));
    await tester.pump();
    expect(find.text('Apparence'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Apparence'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Tout est calme'), findsOneWidget);
  });

  testWidgets('failed-save trial keeps its values and explicitly retries the save', (tester) async {
    await tester.pumpWidget(page(const SettingsTrial(saveError: true)));
    await tester.tap(find.text('Clair'));
    await tester.pump();
    expect(find.text('Sauvegarde impossible'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(find.text('Sauvegarde impossible'), findsNothing);
    expect(tester.widget<SettingChoice>(find.byType(SettingChoice).first).selected, 1);
    expect(tester.takeException(), isNull);
  });
}
