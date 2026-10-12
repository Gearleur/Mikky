import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/ui/foundation/status.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky/ui/pixels/status_stack.dart';

Widget host(List<StackStar> stars, {int? number, bool still = false}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: MikkyUiTheme(
      ui: MikkyUi.dark,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusStack(stars: stars),
            StackNumber(number),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('stars come, slide and go, then nothing ticks', (tester) async {
    const a = (key: 'a', status: UiStatus.working), b = (key: 'b', status: UiStatus.limited);
    await tester.pumpWidget(host([a]));
    // In place at once: nothing to move.
    expect(tester.binding.transientCallbackCount, 0);
    // Built again as is (the island redraws often): still nothing.
    await tester.pumpWidget(host([a]));
    expect(tester.binding.transientCallbackCount, 0);

    // B comes in front: it dissolves in, A slides back.
    await tester.pumpWidget(host([b, a]));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    // Too many: their number; then they go.
    await tester.pumpWidget(
      host([b, a, a, a].indexed.map((e) => (key: e.$1, status: e.$2.status)).toList(), number: 4),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('4'), findsOneWidget);
    await tester.pumpWidget(host(const []));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('animations off: in place at once', (tester) async {
    Widget still(List<StackStar> stars) => host(stars, still: true);
    await tester.pumpWidget(still(const [(key: 'a', status: UiStatus.working)]));
    await tester.pumpWidget(still(const [(key: 'b', status: UiStatus.working), (key: 'a', status: UiStatus.working)]));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
