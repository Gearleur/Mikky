import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_settings_top.dart';
import 'package:mikky/home/home_frame.dart';
import 'package:mikky/settings/settings_top_view.dart';
import 'package:mikky/theme.dart';
import 'package:mikky/ui/controls/pixel_slider.dart';
import 'package:mikky/ui/foundation/tokens.dart';

import 'load_fonts.dart';

Widget page(Widget child, {bool reduced = true}) => WidgetsApp(
  color: MikkyUi.light.island,
  builder: (_, _) => MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: MikkyUiScope(
      ui: MikkyUi.light,
      child: Center(child: child),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('top settings fit the unchanged notch and close back to the home', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(page(const SettingsTopPreview(initiallyOpen: true)));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(HomeFrame)), const Size(700, 200));
      expect(find.byType(SettingsTopView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Thème Sombre'));
      await tester.pump();
      expect(tester.widget<SettingsTopView>(find.byType(SettingsTopView)).settings.theme, ThemeChoice.dark);
      await tester.tap(find.bySemanticsLabel('Sons'));
      await tester.pump();
      expect(tester.widget<PixelSlider>(find.byType(PixelSlider)).onChanged, isNull);
      expect(tester.widget<PixelSlider>(find.byType(PixelSlider)).value, .5);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsTopView), findsNothing);
      expect(tester.getSize(find.byType(HomeFrame)), const Size(700, 200));
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('pixel volume supports drag, bounds and keyboard with no idle ticker', (tester) async {
    await tester.pumpWidget(page(const PixelSliderTrial(initial: .5), reduced: false));
    final slider = find.byType(PixelSlider);
    final box = tester.getRect(slider);
    await tester.tapAt(Offset(box.left + 2, box.center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<PixelSlider>(slider).value, 0);
    await tester.dragFrom(Offset(box.left + 8, box.center.dy), Offset(box.width + 20, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<PixelSlider>(slider).value, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(tester.widget<PixelSlider>(slider).value, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<PixelSlider>(slider).value, closeTo(.05, .001));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(tester.widget<PixelSlider>(slider).value, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('disabled pixel volume ignores pointer input and remains accessible', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(page(const SizedBox(width: 180, child: PixelSlider(value: .5))));
      expect(find.bySemanticsLabel('Volume'), findsOneWidget);
      await tester.tap(find.byType(PixelSlider));
      await tester.drag(find.byType(PixelSlider), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<PixelSlider>(find.byType(PixelSlider)).value, .5);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
