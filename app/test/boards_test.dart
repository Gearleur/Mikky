import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/boards_app.dart';
import 'package:mikky/ui/tokens.dart';

import 'load_fonts.dart';

/// Golden images of the design boards (`mikky.exe --kit`), one per board
/// and theme, animations frozen. Update with `flutter test
/// --update-goldens test/boards_test.dart`, then look.
void main() {
  setUpAll(loadAppFonts);

  for (final spec in boards) {
    for (final (name, ui) in [('light', MikkyUi.light), ('dark', MikkyUi.dark)]) {
      testWidgets('board ${spec.name}, $name', (tester) async {
        const key = Key('band');
        Widget page() => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              child: RepaintBoundary(key: key, child: BoardBand(spec: spec, ui: ui)),
            ),
          ),
        );
        await tester.pumpWidget(page());
        // The board's own size, then a window that fits it.
        final size = tester.getSize(find.byKey(key));
        await tester.binding.setSurfaceSize(size);
        tester.view.devicePixelRatio = 1;
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(page());
        await tester.pump(const Duration(milliseconds: 500));
        await expectLater(find.byKey(key), matchesGoldenFile('goldens/boards/${spec.name.toLowerCase()}_$name.png'));
      });
    }
  }
}
