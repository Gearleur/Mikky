import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/ui/kit_app.dart';
import 'package:mikky/ui/tokens.dart';

/// Golden images of the UI kit (A3), light and dark, animations frozen
/// where the prototypes' `#calme` captures freeze them. Compare with
/// `design/prototypes/composants.html` and `ux-a.html`. Update with
/// `flutter test --update-goldens test/ui_kit_test.dart`, then look.
Future<void> _loadFonts() async {
  for (final (family, files) in [
    ('Geist', ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf']),
    ('Geist Mono', ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final (name, ui) in [('light', MikkyUi.light), ('dark', MikkyUi.dark)]) {
    testWidgets('kit, $name', (tester) async {
      const size = Size(1320, 2320);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const board = Key('board');
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: size, disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextEditingShortcuts(
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(key: board, child: SizedBox(width: size.width, child: KitBoard(ui: ui))),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      await expectLater(find.byKey(board), matchesGoldenFile('goldens/ui_kit_$name.png'));
    });
  }
}
