import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/canvas.dart';

/// The boards' canvas moves as in Figma: a drag anywhere, even on a frame
/// (a click stays a click), Space held, or the middle button.
void main() {
  Future<(Finder, List<int>)> pumpCanvas(WidgetTester tester) async {
    final taps = <int>[];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: BoardCanvas(
        background: const Color(0xFFFFFFFF),
        child: GestureDetector(
          onTap: () => taps.add(1),
          child: const SizedBox(key: Key('frame'), width: 300, height: 300, child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
    ));
    return (find.byKey(const Key('frame')), taps);
  }

  testWidgets('a drag on a frame moves the canvas, a click still reaches it', (tester) async {
    final (frame, taps) = await pumpCanvas(tester);
    final before = tester.getTopLeft(frame);
    await tester.tap(frame);
    expect(taps, [1]);
    await tester.drag(frame, const Offset(-120, -80));
    await tester.pump();
    final moved = tester.getTopLeft(frame) - before;
    // The recognizer keeps the slop for itself; the rest moves the canvas.
    expect(moved.dx, lessThan(-90));
    expect(moved.dy, lessThan(-50));
    expect(taps, [1]);
  });

  testWidgets('the middle button moves it too', (tester) async {
    final (frame, _) = await pumpCanvas(tester);
    final before = tester.getTopLeft(frame);
    final g = await tester.startGesture(tester.getCenter(frame), buttons: kMiddleMouseButton, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(50, 40));
    await g.up();
    await tester.pump();
    expect(tester.getTopLeft(frame) - before, const Offset(50, 40));
  });

  testWidgets('Space held: the frames do not see the mouse', (tester) async {
    final (frame, taps) = await pumpCanvas(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.tap(frame, warnIfMissed: false);
    expect(taps, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.tap(frame);
    expect(taps, [1]);
  });
}
