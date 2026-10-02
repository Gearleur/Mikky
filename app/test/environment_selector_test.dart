import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/ui/environment_selector.dart';
import 'package:mikky/ui/floating_menu.dart';
import 'package:mikky/ui/pixel_fx.dart';
import 'package:mikky/ui/tokens.dart';

void main() {
  testWidgets(
    'shared menu opens from label and star without moving the layout',
    (tester) async {
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
      final box = tester.widget<AnimatedContainer>(find.descendant(of: find.byType(EnvironmentSelector), matching: find.byType(AnimatedContainer)));
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
    },
  );
}
