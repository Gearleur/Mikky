import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_home.dart';
import 'package:mikky/ui/controls/environment_selector.dart';
import 'package:mikky/ui/controls/sliding_hover.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky/ui/overlays/floating_menu.dart';
import 'package:mikky/ui/pixels/pixel_fx.dart';

import 'load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final (theme, ui) in [('light', MikkyUi.light), ('dark', MikkyUi.dark)]) {
    testWidgets('compact $theme selector keeps names and the active choice visible', (tester) async {
      const preview = Key('selector-preview');
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MikkyUiTheme(
              ui: ui,
              child: const Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(key: preview, child: SelectorTry(small: true)),
              ),
            ),
          ),
        ),
      );
      final button = tester.getRect(find.byType(EnvironmentSelector));
      await tester.tap(find.text('Local'));
      await tester.pumpAndSettle();
      // The complete menu is above the compact button, which remains visible.
      expect(find.text('Local'), findsNWidgets(2));
      expect(tester.getRect(find.byType(SlidingHover)).bottom, lessThan(button.top));
      for (final environment in MikkyEnvironment.values) {
        expect(tester.renderObject<RenderParagraph>(find.text(environment.label).last).didExceedMaxLines, isFalse);
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(find.text('WSL')));
      await tester.pumpAndSettle();
      // Hovering WSL must not take away Local's selected surface.
      final marker = find.descendant(of: find.byType(SlidingHover), matching: find.byType(AnimatedOpacity));
      expect(tester.widget<AnimatedOpacity>(marker).opacity, 1);
      expect(tester.getRect(marker).contains(tester.getCenter(find.text('Local').last)), isTrue);
      await expectLater(find.byKey(preview), matchesGoldenFile('goldens/environment_selector_$theme.png'));
      await mouse.removePointer();

      for (final environment in [
        MikkyEnvironment.wsl,
        MikkyEnvironment.vps,
        MikkyEnvironment.cloud,
        MikkyEnvironment.local,
      ]) {
        await tester.tap(find.text(environment.label).last);
        await tester.pumpAndSettle();
        expect(tester.widget<EnvironmentSelector>(find.byType(EnvironmentSelector)).selected, environment);
        expect(find.text(environment.label), findsOneWidget);
        expect(tester.getRect(find.byType(EnvironmentSelector)), button);
        await tester.tap(find.byType(PixelStar));
        await tester.pumpAndSettle();
        final chosen = find.text(environment.label).last;
        expect(tester.renderObject<RenderParagraph>(chosen).didExceedMaxLines, isFalse);
        expect(tester.getRect(marker).contains(tester.getCenter(chosen)), isTrue);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shared menu opens from label and star without moving the layout', (tester) async {
    var selected = MikkyEnvironment.local;
    final layer = OverlayEntry(
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Stack(
          children: [
            Positioned(
              top: 30,
              right: 30,
              child: EnvironmentSelector(
                selected: selected,
                menuWithin: context,
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiTheme(
            ui: MikkyUi.light,
            child: Overlay(initialEntries: [layer]),
          ),
        ),
      ),
    );
    final resting = tester.getRect(find.byType(EnvironmentSelector));
    expect(find.byType(PixelStar), findsOneWidget);
    expect(find.text('VPS'), findsNothing);
    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(EnvironmentSelector)), resting);
    expect(find.text('VPS'), findsOneWidget);
    await tester.tap(find.text('VPS'));
    await tester.pumpAndSettle();
    expect(selected, MikkyEnvironment.vps);
    expect(find.text('Local'), findsNothing);
    expect(FloatingMenu.covering.value, isNull);
    // As wide as the longest name: it does not move with the choice.
    expect(tester.getRect(find.byType(EnvironmentSelector)), resting);
    // Back to flat after a mouse choice: no fill, no ring (2026-10-02).
    final box = tester.widget<AnimatedContainer>(
      find.descendant(of: find.byType(EnvironmentSelector), matching: find.byType(AnimatedContainer)),
    );
    final look = box.decoration! as BoxDecoration;
    expect(look.color!.a, 0);
    expect((look.border! as Border).top.color, isNot(MikkyUi.light.ink));

    await tester.tap(find.byType(PixelStar));
    await tester.pumpAndSettle();
    expect(find.text('Local'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Local'), findsNothing);
    expect(tester.getRect(find.byType(EnvironmentSelector)), resting);
    expect(selected, MikkyEnvironment.vps);
    expect(FloatingMenu.covering.value, isNull);

    await tester.tap(find.byType(PixelStar));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 550));
    await tester.pumpAndSettle();
    expect(find.text('Local'), findsNothing);
    expect(selected, MikkyEnvironment.vps);
    layer.remove();
    layer.dispose();
    await tester.pump();
  });
}
