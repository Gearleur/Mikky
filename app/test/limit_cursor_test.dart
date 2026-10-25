import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/side/session_cards.dart';
import 'package:mikky/ui/foundation/selection.dart';
import 'package:mikky/ui/foundation/tokens.dart';

import 'load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  testWidgets('limit actions keep their hand cursor inside a selectable conversation', (tester) async {
    var finished = 0, relaunched = 0;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xffffffff),
        builder: (context, _) => Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => MikkyUiScope(
                ui: MikkyUi.light,
                child: SelectableArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 560,
                      child: LimitCard(
                        message: 'Limite simulée',
                        onFinish: () => finished++,
                        onSpell: () => relaunched++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 1);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    for (final label in ['Terminer', 'Relance auto']) {
      await mouse.moveTo(tester.getCenter(find.text(label)));
      await tester.pumpAndSettle();
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
      await tester.tap(find.text(label));
    }
    expect((finished, relaunched), (1, 1));
    expect(tester.takeException(), isNull);
  });
}
