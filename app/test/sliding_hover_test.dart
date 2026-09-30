import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/ui/sliding_hover.dart';
import 'package:mikky/ui/tokens.dart';

/// The hover of a list is the white square of the Oui / Non answers: it
/// comes under the row under the mouse, slides to the next one, and goes
/// back to rest on the chosen row.
void main() {
  Future<void> pump(WidgetTester tester, {int? selected, bool follow = true}) => tester.pumpWidget(MikkyUiTheme(
    ui: MikkyUi.light,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          child: SlidingHover(
            followHover: follow,
            child: Column(children: [
              for (var i = 0; i < 3; i++)
                HoverTarget(selected: i == selected, child: SizedBox(key: Key('row$i'), width: 200, height: 40)),
            ]),
          ),
        ),
      ),
    ),
  ));

  /// The square's place, or null when there is none.
  Rect? marker(WidgetTester tester) {
    final f = find.byWidgetPredicate((w) => w is Positioned);
    return f.evaluate().isEmpty ? null : tester.getRect(f.first);
  }

  testWidgets('comes under the hovered row, then slides to the next', (tester) async {
    await pump(tester);
    await tester.pump();
    expect(marker(tester), isNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byKey(const Key('row0'))));
    await tester.pump();
    expect(marker(tester), tester.getRect(find.byKey(const Key('row0'))));
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('row2'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    // On its way.
    final mid = marker(tester)!;
    expect(mid.top, greaterThan(0));
    expect(mid.top, lessThan(80));
    await tester.pumpAndSettle();
    expect(marker(tester)!.top, closeTo(80, .5));
    await mouse.removePointer();
  });

  testWidgets('rests on the chosen row when the mouse leaves', (tester) async {
    await pump(tester, selected: 1);
    await tester.pump();
    await tester.pump();
    expect(marker(tester)!.top, closeTo(40, .5));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byKey(const Key('row2'))));
    await tester.pumpAndSettle();
    expect(marker(tester)!.top, closeTo(80, .5));
    await mouse.moveTo(const Offset(500, 500));
    await tester.pumpAndSettle();
    expect(marker(tester)!.top, closeTo(40, .5));
    await mouse.removePointer();
  });

  testWidgets('as an indicator: slides to the new choice, down as well as up', (tester) async {
    for (final (from, to) in [(0, 2), (2, 0)]) {
      await pump(tester, selected: from, follow: false);
      await tester.pumpAndSettle();
      expect(marker(tester)!.top, closeTo(from * 40.0, .5));
      await pump(tester, selected: to, follow: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // On its way, not hidden then back.
      final mid = marker(tester)!.top;
      expect(mid, inExclusiveRange(1, 79), reason: '$from → $to');
      await tester.pumpAndSettle();
      expect(marker(tester)!.top, closeTo(to * 40.0, .5));
    }
  });
}
