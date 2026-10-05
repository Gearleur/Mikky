import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/home/home_view.dart';
import 'package:mikky/home/task_glance.dart';
import 'package:mikky/ui/app_tile.dart';
import 'package:mikky/ui/environment_selector.dart';
import 'package:mikky/ui/page_dots.dart';
import 'package:mikky/ui/tokens.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  Widget host(Widget child) => MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MikkyUiTheme(ui: MikkyUi.light, child: Align(alignment: Alignment.topLeft, child: child)),
    ),
  );

  int page(WidgetTester tester) => tester.widget<PageDots>(find.byType(PageDots)).page;

  testWidgets('notch: pages by arrows, dots and keys, arrows hidden at the ends', (tester) async {
    // Nothing at work: three columns, six wide tiles a page.
    await tester.pumpWidget(host(HomeView(layout: HomeLayout.top, apps: HomeApp.placeholders(14), animate: false)));
    expect(tester.widget<PageDots>(find.byType(PageDots)).count, 3);
    expect(find.byType(AppTile), findsNWidgets(6));
    expect(tester.getSize(find.byType(AppTile).first), const Size(168, 44));
    expect(page(tester), 0);

    await tester.tap(find.bySemanticsLabel('Page suivante'));
    await tester.pumpAndSettle();
    expect(page(tester), 1);

    // A click in the home gives it the arrow keys.
    await tester.tap(find.byType(AppTile).first, warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(page(tester), 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(page(tester), 2, reason: 'no page after the last');

    // The last page: its two apps only, no empty places.
    expect(find.byType(AppTile), findsNWidgets(2));
    expect(find.byType(AppSlot), findsNothing);
    final next = tester.widget<AnimatedOpacity>(find.ancestor(of: find.bySemanticsLabel('Page suivante'), matching: find.byType(AnimatedOpacity)).first);
    expect(next.opacity, 0);
  });

  testWidgets('notch: a dot goes to its page', (tester) async {
    await tester.pumpWidget(host(HomeView(layout: HomeLayout.top, apps: HomeApp.placeholders(14), animate: false)));
    final dots = tester.getRect(find.byType(PageDots));
    await tester.tapAt(Offset(dots.left + PageDots.star / 2 + 2 * PageDots.step, dots.center.dy));
    await tester.pumpAndSettle();
    expect(page(tester), 2);
  });

  testWidgets('one page: no dots shown, the modes switch to the chat', (tester) async {
    await tester.pumpWidget(host(HomeView(layout: HomeLayout.top, apps: HomeApp.placeholders(6), animate: false)));
    expect(tester.widget<PageDots>(find.byType(PageDots)).count, 1);
    expect(find.byType(AppTile), findsNWidgets(6));
    await tester.tap(find.bySemanticsLabel('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Le chat · à dessiner'), findsOneWidget);
    expect(find.byType(AppTile), findsNothing);
  });

  testWidgets('the tools go to the Chat; its foot fades; launched, back to the apps', (tester) async {
    VoidCallback? toApps;
    await tester.pumpWidget(host(HomeView(
      layout: HomeLayout.top,
      apps: HomeApp.placeholders(3),
      animate: false,
      onHistory: (_) {},
      chat: (back) {
        toApps = back;
        return const Text('nouvelle tâche');
      },
    )));
    // No « + » in the notch: the tools and the modes start a task.
    expect(find.byType(AddTile), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp('^Outils')));
    await tester.pumpAndSettle();
    expect(find.text('nouvelle tâche'), findsOneWidget);
    expect(find.byType(AppTile), findsNothing);
    final foot = tester.widget<AnimatedOpacity>(find.ancestor(of: find.byType(EnvironmentSelector), matching: find.byType(AnimatedOpacity)).first);
    expect(foot.opacity, 0);

    toApps!();
    await tester.pumpAndSettle();
    expect(find.text('nouvelle tâche'), findsNothing);
    expect(find.byType(AppTile), findsNWidgets(3));
  });

  testWidgets('notch: the task Mikky looks at beside him, two columns, a click opens it', (tester) async {
    HomeApp? opened;
    final log = SessionLog()
      ..applyAll([
        TurnStarted(at: DateTime(2026, 10, 5, 14)),
        UserMessage('Corrige', at: DateTime(2026, 10, 5, 14)),
        const ToolCallEvent('1', kind: ToolKind.read, title: 'Lire a.dart', path: 'a.dart', status: ToolStatus.running),
      ]);
    await tester.pumpWidget(host(HomeView(
      layout: HomeLayout.top,
      apps: HomeApp.placeholders(9),
      watched: WatchedTask(id: 'w', name: 'Corrige les tests', log: log, status: AgentStatus.working, app: AgentApp.vscode),
      animate: false,
      onOpen: (a) => opened = a,
    )));
    expect(find.byType(TaskGlance), findsOneWidget);
    expect(find.text('VS Code'), findsOneWidget);
    expect(find.text('Lit a.dart'), findsOneWidget);
    // Two columns beside the task: four apps a page, three pages.
    expect(find.byType(AppTile), findsNWidgets(4));
    expect(tester.widget<PageDots>(find.byType(PageDots)).count, 3);
    // The task clear of the apps and of their left arrow.
    expect(tester.getRect(find.byType(TaskGlance)).right, lessThan(tester.getRect(find.byType(AppTile).first).left - 22));
    await tester.tap(find.text('Corrige les tests'));
    await tester.pump();
    expect(opened?.id, 'w');
  });

  testWidgets('back from the Chat, it is gone at once; to the Chat, a soft fade', (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MikkyUiTheme(
        ui: MikkyUi.light,
        child: Align(
          alignment: Alignment.topLeft,
          child: HomeView(layout: HomeLayout.top, apps: HomeApp.placeholders(3), animate: false, chat: (_) => const Text('nouvelle tâche')),
        ),
      ),
    ));
    await tester.tap(find.bySemanticsLabel('Chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Halfway through the soft fade, the tiles are still leaving.
    expect(find.byType(AppTile), findsWidgets);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Applications'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('nouvelle tâche'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('right: the top upright, eight tiles a page in 2 × 4, sideways pages, and the environment menu', (tester) async {
    await tester.pumpWidget(host(HomeView(layout: HomeLayout.right, apps: HomeApp.placeholders(20), animate: false)));
    expect(tester.widget<PageDots>(find.byType(PageDots)).count, 3);
    expect(find.byType(AppTile), findsNWidgets(8));
    final a = tester.getRect(find.byType(AppTile).at(0)), b = tester.getRect(find.byType(AppTile).at(1)), c = tester.getRect(find.byType(AppTile).at(2));
    expect(a.size, const Size(64, 64));
    expect(a.top, b.top);
    expect(c.left, a.left);
    expect(c.top - a.bottom, HomeLayout.right.rowGap);
    expect(b.left - a.right, HomeLayout.right.gap);
    // The whole page inside the island, above the dots; the arrows clear
    // of the tiles.
    expect(tester.getRect(find.byType(AppTile).at(7)).bottom, lessThan(tester.getRect(find.byType(PageDots)).top));
    expect(tester.getRect(find.bySemanticsLabel('Page suivante')).left, greaterThan(tester.getRect(find.byType(AppTile).at(1)).right));

    // Dragged to the left with the mouse: the next page.
    await tester.dragFrom(a.center, const Offset(-260, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(page(tester), 1);

    // The wheel: one page per notch.
    await tester.sendEventToBinding(PointerScrollEvent(position: a.center, scrollDelta: const Offset(0, 100)));
    await tester.pumpAndSettle();
    expect(page(tester), 2);

    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WSL'));
    await tester.pumpAndSettle();
    expect(find.text('WSL'), findsOneWidget);
    expect(tester.widget<EnvironmentSelector>(find.byType(EnvironmentSelector)).selected, MikkyEnvironment.wsl);
  });

  testWidgets('a tile opens its app, the tools and « + » a new task; empty places keep a token', (tester) async {
    HomeApp? opened;
    var tools = 0;
    await tester.pumpWidget(host(HomeView(
      layout: HomeLayout.right,
      apps: HomeApp.placeholders(3),
      animate: false,
      onOpen: (a) => opened = a,
      onNew: () => tools++,
    )));
    await tester.tap(find.byType(AppTile).at(1));
    await tester.pump();
    expect(opened?.id, 'app-1');
    await tester.tap(find.bySemanticsLabel(RegExp('^Outils')));
    await tester.pump();
    expect(tools, 1);
    // « + » after the apps starts a task too; the free places keep a token.
    await tester.tap(find.byKey(const ValueKey('add')));
    await tester.pump();
    expect(tools, 2);
    expect(find.byType(AppSlot), findsNWidgets(4));

    await tester.pumpWidget(host(HomeView(layout: HomeLayout.right, animate: false)));
    // Nothing to launch from there: no « + », eight waiting tokens.
    expect(find.byType(AppTile), findsNothing);
    expect(find.byType(AppSlot), findsNWidgets(8));

    // The notch keeps no place for nothing.
    await tester.pumpWidget(host(HomeView(layout: HomeLayout.top, animate: false, onNew: () {})));
    expect(find.byType(AppTile), findsNothing);
    expect(find.byType(AppSlot), findsNothing);
  });

  testWidgets('« + » takes a place: eight apps and « + » make two pages at the right', (tester) async {
    await tester.pumpWidget(host(HomeView(layout: HomeLayout.right, apps: HomeApp.placeholders(8), animate: false, onNew: () {})));
    expect(tester.widget<PageDots>(find.byType(PageDots)).count, 2);
    expect(find.byKey(const ValueKey('add')), findsNothing);
    await tester.tap(find.bySemanticsLabel('Page suivante'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('add')), findsOneWidget);
    expect(find.byType(AppSlot), findsNWidgets(7));
  });
}
