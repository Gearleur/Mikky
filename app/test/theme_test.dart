import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_theme.dart';
import 'package:mikky/boards/boards_app.dart';
import 'package:mikky/boards/canvas.dart';
import 'package:mikky/settings/settings_top_view.dart';
import 'package:mikky/theme.dart';
import 'package:mikky/ui/brand/app_tile.dart';
import 'package:mikky/ui/brand/brand_logo.dart';
import 'package:mikky/ui/content/history_view.dart';
import 'package:mikky/ui/foundation/tokens.dart';

import 'load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  test('the approved surfaces are the actual dark theme, including the island', () {
    expect(MikkyUi.dark.island, const Color(0xFF171717));
    expect(MikkyUi.dark.tileColor, const Color(0xFF2C2C30));
    expect(MikkyUi.dark.tileColor, MikkyUi.dark.thumb);
    expect(MikkyUi.dark.appsBackground, MikkyUi.dark.island);
    expect(MikkyTheme.resolve(ThemeChoice.dark, Brightness.light).ui, same(MikkyUi.dark));
    expect(MikkyUi.light.tileColor, const Color(0xFFFFFFFF));
    expect(MikkyUi.light.island, const Color(0xFFFFFFFF));
  });

  testWidgets('app tiles switch between the existing dark and light logo/text colors', (tester) async {
    for (final ui in [MikkyUi.dark, MikkyUi.light, MikkyUi.dark]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiScope(
            ui: ui,
            child: const Center(child: AppTile(child: BrandLogo(Brand.codex))),
          ),
        ),
      );
      final context = tester.element(find.byType(BrandLogo));
      expect(MikkyUi.of(context), same(ui));
      expect(AppTileInk.maybeOf(context)?.text, ui.tileText);
      expect(AppTileInk.maybeOf(context)?.secondary, ui.tileText2);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('applied theme across home history and settings', tags: 'golden', (tester) async {
    tester.view.devicePixelRatio = 1;
    await tester.binding.setSurfaceSize(const Size(2400, 610));
    addTearDown(tester.view.reset);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const key = Key('palette-comparison');
    final spec = BoardSpec(
      'Thème sombre appliqué',
      'Fonds et applications uniquement',
      (_) => [appliedThemeSection(MikkyUi.dark)],
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: BoardBand(spec: spec, ui: MikkyUi.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HistoryView), findsOneWidget);
    expect(find.byType(SettingsTopView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/boards/applied_theme.png'));
  });
}
