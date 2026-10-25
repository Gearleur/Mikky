import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/boards/board_components_history.dart';
import 'package:mikky/home/history_sheet.dart';
import 'package:mikky/home/home_layout.dart';
import 'package:mikky/home/home_view.dart';
import 'package:mikky/island/island_clip.dart';
import 'package:mikky/overlay/overlay_channel.dart';
import 'package:mikky/ui/content/history_view.dart';
import 'package:mikky/ui/foundation/tokens.dart';
import 'package:mikky/ui/overlays/floating_menu.dart';
import 'package:mikky/ui/overlays/sheet.dart';
import 'package:mikky/ui/overlays/sheet_host.dart';

import 'load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final layout in [HomeLayout.top, HomeLayout.right]) {
    testWidgets(
      'history covers the separate mascot layer and keeps the ${layout.isTop ? 'top' : 'right'} window clip',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(840, 620));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final capture = GlobalKey();
        var mascotTaps = 0;
        Future<void>? closed;
        const shift = Offset(28, 24);
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MikkyUiTheme(
                ui: MikkyUi.light,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: capture,
                    child: Padding(
                      padding: EdgeInsets.only(left: shift.dx, top: shift.dy),
                      child: SizedBox.fromSize(
                        size: layout.size,
                        child: SheetHost(
                          clipper: IslandClip(Offset.zero & layout.size, 30),
                          roundClipper: IslandRoundClip(Offset.zero & layout.size, 30),
                          child: Stack(
                            children: [
                              HomeView(
                                layout: layout,
                                drawMikky: false,
                                animate: false,
                                onHistory: (within) => closed = showHistory(within, rows: historyTopSamples),
                              ),
                              // Same stacking as IslandView: Mikky is painted AFTER
                              // the home, outside its private Overlay.
                              Positioned(
                                left: 8,
                                top: 8,
                                width: 100,
                                height: layout.size.height - 16,
                                child: GestureDetector(
                                  onTap: () => mascotTaps++,
                                  child: const ColoredBox(color: Color(0xFFFF0000)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        Future<Color> pixel(Offset point) async {
          final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          return (await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData();
            final i = ((point.dy.toInt() * image.width) + point.dx.toInt()) * 4;
            final color = Color.fromARGB(
              bytes!.getUint8(i + 3),
              bytes.getUint8(i),
              bytes.getUint8(i + 1),
              bytes.getUint8(i + 2),
            );
            image.dispose();
            return color;
          }))!;
        }

        final panePoint = shift + Offset(82, layout.size.height / 2);
        expect(await pixel(panePoint), const Color(0xFFFF0000));
        await tester.tap(find.bySemanticsLabel('Historique'));
        await tester.pumpAndSettle();
        expect(find.byType(HistoryView), findsOneWidget);
        final panel = tester.getRect(find.byKey(const ValueKey('history-top-list')));
        expect(panel.top, closeTo(shift.dy + HistoryView.inset, .01));
        expect(panel.left, closeTo(shift.dx + 64, .01));
        // The white pane must occlude the red foreground, and the backdrop
        // must shade the mascot in the narrow gap between pane and rail.
        expect(await pixel(panePoint), const Color(0xFFFFFFFF));
        final shaded = await pixel(shift + Offset(58, layout.size.height / 2));
        expect(shaded.r, lessThan(1));
        expect(shaded.g, lessThan(.02));
        expect(shaded.b, lessThan(.02));
        // The sheet's backdrop is clipped at the corner; content outside
        // that curve (such as the island's shadow) remains untouched.
        expect((await pixel(shift + const Offset(8, 8))).r, greaterThan(.99));

        await tester.tapAt(shift + Offset(58, layout.size.height / 2));
        await tester.pumpAndSettle();
        await closed;
        expect(find.byType(HistoryView), findsNothing);
        expect(mascotTaps, 0);
        expect(await pixel(panePoint), const Color(0xFFFF0000));
        await tester.tapAt(panePoint);
        expect(mascotTaps, 1);

        // Tear down with an open sheet: listeners and the returned Future
        // must be released even when the whole island is removed.
        await tester.tap(find.bySemanticsLabel('Historique'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await closed;
      },
    );
  }

  testWidgets('hiding the window releases its modal even during the closing animation', (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    Future<void>? closed;
    late BuildContext sheet;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiTheme(
            ui: MikkyUi.light,
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, enabled, child) => SheetHost(enabled: enabled, child: child!),
              child: Builder(
                builder: (within) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => closed = showSheetPage(
                    within,
                    builder: (context) {
                      sheet = context;
                      return const ColoredBox(color: Color(0xFFFFFFFF));
                    },
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 200));
    await tester.pumpAndSettle();
    expect(find.byType(SheetScene), findsOneWidget);
    final dismissing = Sheet.dismiss(sheet);
    await tester.pump(const Duration(milliseconds: 40));
    visible.value = false;
    await tester.pumpAndSettle();
    await closed;
    await dismissing;
    expect(find.byType(SheetScene, skipOffstage: false), findsNothing);
    expect(tester.binding.hasScheduledFrame, false);
  });

  testWidgets('history actions stay in the notch inside the larger transparent desktop window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(840, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FloatingMenu.track();
    final sideArea = GlobalKey();
    const notch = Rect.fromLTWH(70, 0, 700, 200);
    const entries = [
      MenuEntry(1, 'Ouvrir dans VS Code', icon: 'code'),
      MenuEntry(2, 'Ouvrir le dossier', icon: 'folder'),
      MenuEntry.separator(),
      MenuEntry(3, 'Renommer…', icon: 'edit'),
      MenuEntry(4, 'Épingler', icon: 'pin'),
      MenuEntry(5, 'Archiver', icon: 'archive'),
      MenuEntry.separator(),
      MenuEntry(6, 'Supprimer…', icon: 'trash'),
    ];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MikkyUiTheme(
            ui: MikkyUi.light,
            child: SheetHost(
              clipper: const IslandClip(notch, 30),
              roundClipper: const IslandRoundClip(notch, 30),
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: notch,
                    child: KeyedSubtree(
                      key: sideArea,
                      child: HomeView(
                        drawMikky: false,
                        animate: false,
                        onHistory: (within) => showHistory(
                          within,
                          rows: historyTopSamples,
                          // IslandView opens menus from the underlying side area,
                          // above the history in the outer 840 × 480 Overlay.
                          onMenu: (_, _) => showFloatingMenu(sideArea.currentContext!, entries),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Historique'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Menu de Prépare la démo de l’île'));
    await tester.pumpAndSettle();
    final action = find.text('Supprimer…');
    final panel = tester.getRect(find.ancestor(of: action, matching: find.byType(ClipRRect)).first);
    expect(panel.left, greaterThanOrEqualTo(notch.left + 12));
    expect(panel.top, greaterThanOrEqualTo(notch.top + 12));
    expect(panel.right, lessThanOrEqualTo(notch.right - 12));
    expect(panel.bottom, lessThanOrEqualTo(notch.bottom - 12));
    expect(panel.width, lessThan(220));
    expect(action.hitTestable(), findsOneWidget);
    final viewport = find.ancestor(of: action, matching: find.byType(SingleChildScrollView));
    final scrolling = tester.state<ScrollableState>(find.descendant(of: viewport, matching: find.byType(Scrollable)));
    expect(scrolling.position.maxScrollExtent, 0);
    FloatingMenu.dismissAll();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
