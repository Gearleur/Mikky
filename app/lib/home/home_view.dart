import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/app_tile.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/edge_rail.dart';
import '../ui/environment_selector.dart';
import '../ui/motion.dart';
import '../ui/page_dots.dart';
import '../ui/side.dart';
import '../ui/status.dart';
import '../ui/surface.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';
import 'tools_rail.dart';

/// Where the home lives: the wide island at the top, or the tall one at
/// the right edge.
enum HomePlacement { top, right }

/// The home's measures in one placement (design.md §7, « Accueil Top et
/// Right », 2026-10-02): the window and its pages of tiles. Set for the
/// island's real sizes, not scaled from the mockups.
class HomeLayout {
  const HomeLayout._({
    required this.placement,
    required this.size,
    required this.radius,
    required this.columns,
    required this.rows,
    required this.tile,
    required this.gap,
    required this.rowGap,
    required this.gridTop,
    required this.arrowInset,
  });

  /// Top: the island opened to 450 × 260 (taller than the old 450 × 180,
  /// chosen by the user; its overlay window, 560 × 320, will need ~40 px
  /// more for the shadow), pages of two rows of four 64 px tiles. Bar,
  /// tiles and foot 10 px apart.
  static const top = HomeLayout._(
    placement: HomePlacement.top,
    size: Size(450, 260),
    radius: 30,
    columns: 4,
    rows: 2,
    tile: 64,
    gap: 16,
    rowGap: 10,
    gridTop: barTop + barHeight + 10,
    arrowInset: 18,
  );

  /// Right: the island opened to 344 × 520 (`IslandMetrics.right`), pages
  /// of six 100 px tiles (2 × 3, user request 2026-10-02), sliding sideways
  /// like the top's; in the middle between the bar and the dots.
  static const right = HomeLayout._(
    placement: HomePlacement.right,
    size: Size(344, 520),
    radius: 38,
    columns: 2,
    rows: 3,
    tile: 100,
    gap: 24,
    rowGap: 20,
    gridTop: 72,
    arrowInset: 14,
  );

  final HomePlacement placement;
  final Size size;

  /// The corners away from the screen's edge.
  final double radius;

  /// Tiles per row, rows per page.
  final int columns, rows;
  final double tile, gap, rowGap;

  /// Where the first row starts; the arrows' distance from the edges.
  final double gridTop, arrowInset;

  bool get isTop => placement == HomePlacement.top;
  int get perPage => columns * rows;
  double get gridWidth => columns * tile + (columns - 1) * gap;
  double get gridHeight => rows * tile + (rows - 1) * rowGap;

  /// The bar of the top: Mikky, the modes or the environment, the tools.
  static const barTop = 12.0, barHeight = 44.0;

  /// Right: the modes at the bottom.
  static const dockHeight = 52.0, dockBottom = 16.0;
  double get mikkySize => 72;
}

/// One app of the home: one or more agents doing a task (user, 2026-10-02).
/// For now one agent; its tile shows its tool and its state until the
/// apps get their own drawing.
class HomeApp {
  const HomeApp({required this.id, this.name = '', this.brand, this.status});

  final String id;
  final String name;

  /// The tool it runs with; null: a neutral tile (the boards).
  final Brand? brand;

  /// Its state, in a pastille on the corner; null: nothing.
  final UiStatus? status;

  /// [n] neutral apps, for the boards.
  static List<HomeApp> placeholders(int n) => [for (var i = 0; i < n; i++) HomeApp(id: 'app-$i', name: 'Application ${i + 1}')];
}

/// The new home (2026-10-02, mockups `docs/notch_haut/`), one widget for
/// both placements: Mikky alive at the top left, the two modes (tiles,
/// chat), the tools on a rail out of the screen's edge, pages of apps
/// (an app: one or more agents doing a task) and « Choisir
/// l'environnement ». The pages slide sideways: drag (mouse, touchpad),
/// wheel, arrows, dots or ← →. Its own Overlay keeps the menus inside it.
/// Not drawn on the island yet: the boards first.
class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    this.layout = HomeLayout.top,
    this.apps = const [],
    this.onOpen,
    this.onTools,
    this.drawMikky = true,
    this.tools = const [Brand.claude, Brand.codex],
    this.environment = MikkyEnvironment.local,
    this.mikky = MikkyState.idle,
    this.animate = true,
  });

  final HomeLayout layout;

  final List<HomeApp> apps;

  /// A tile pressed.
  final ValueChanged<HomeApp>? onOpen;

  /// The tools' rail pressed: a new agent. Null: cannot launch.
  final VoidCallback? onTools;

  /// False: the island draws its own Mikky in his place (the app: he comes
  /// from the closed island to this spot, in the state of his agent).
  final bool drawMikky;
  final List<Brand> tools;
  final MikkyEnvironment environment;

  /// Mikky's state: the agent he follows.
  final MikkyState mikky;

  /// False: Mikky still (goldens).
  final bool animate;


  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late MikkyEnvironment _environment = widget.environment;
  int _mode = 0, _page = 0;
  final _pages = PageController();
  final _keys = FocusNode(debugLabel: 'home');
  late final _layer = OverlayEntry(builder: _window);

  // The wheel: one page per notch, not a page per event of a long roll.
  double _wheel = 0;
  Duration? _wheelAt;

  HomeLayout get _l => widget.layout;
  int get _pageCount => math.max(1, (widget.apps.length / _l.perPage).ceil());

  @override
  void didUpdateWidget(HomeView old) {
    super.didUpdateWidget(old);
    // Fewer apps: no page past the last.
    if (_page > _pageCount - 1) {
      _page = _pageCount - 1;
      if (_pages.hasClients) _pages.jumpToPage(_page);
    }
    _layer.markNeedsBuild();
  }

  @override
  void dispose() {
    _layer.remove();
    _layer.dispose();
    _pages.dispose();
    _keys.dispose();
    super.dispose();
  }

  void _set(VoidCallback f) {
    setState(f);
    _layer.markNeedsBuild();
  }

  void _goTo(int page) {
    final p = page.clamp(0, _pageCount - 1);
    if (p == _page) return;
    _set(() => _page = p);
    if (!_pages.hasClients) return;
    if (Motion.reduced(context)) {
      _pages.jumpToPage(p);
    } else {
      _pages.animateToPage(p, duration: Motion.slide, curve: Motion.enter);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || _mode != 0) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goTo(_page - 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goTo(_page + 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Down or right: the next page; up or left: the one before. Several
  /// pages only: otherwise the wheel stays with what is around.
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _pageCount < 2 || _mode != 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final d = (e as PointerScrollEvent).scrollDelta;
      final delta = d.dx.abs() > d.dy.abs() ? d.dx : d.dy;
      final now = e.timeStamp;
      if (_wheelAt != null && now - _wheelAt! < const Duration(milliseconds: 320)) return;
      _wheel += delta;
      if (_wheel.abs() < 40) return;
      _wheelAt = now;
      final next = _wheel > 0;
      _wheel = 0;
      _goTo(_page + (next ? 1 : -1));
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: _l.size,
    child: Focus(
      focusNode: _keys,
      onKeyEvent: _onKey,
      // A click in the home gives it the arrow keys (unless a control
      // inside takes the focus).
      child: Listener(
        onPointerDown: (_) {
          if (!_keys.hasFocus) _keys.requestFocus();
        },
        child: Overlay(initialEntries: [_layer]),
      ),
    ),
  );

  Widget _window(BuildContext inner) => _l.isTop ? _top(inner) : _right(inner);

  // ------------------------------------------------------------------ parts

  Widget get _mikkyWidget => widget.drawMikky
      ? MiniMikky(size: _l.mikkySize, animate: widget.animate, state: widget.mikky, badge: false)
      : SizedBox.square(dimension: _l.mikkySize);

  Widget _modes(double height) => MTabBar(
    mini: true,
    height: height,
    // The chosen mode in black (2026-10-02): the home's one black, its
    // depth; the arrows stay grey.
    ink: true,
    selected: _mode,
    onChanged: (m) => _set(() => _mode = m),
    items: const [TabItem('grid', label: 'Applications'), TabItem('chat', label: 'Chat')],
  );

  Widget _tools() => ToolsRail(tools: widget.tools, edge: RailEdge.right, height: HomeLayout.barHeight, onPressed: widget.onTools);

  Widget _environmentSelector(BuildContext inner) => EnvironmentSelector(
    selected: _environment,
    menuWithin: inner,
    onChanged: (e) => _set(() => _environment = e),
  );

  Widget _tile(HomeApp app) => AppTile(
    key: ValueKey(app.id),
    size: _l.tile,
    label: app.name,
    status: app.status,
    onTap: () => widget.onOpen?.call(app),
    child: app.brand == null ? null : Center(child: BrandLogo(app.brand!, size: (_l.tile * .34).roundToDouble())),
  );

  /// [count] tiles from [first], in rows of [HomeLayout.columns], the last
  /// row from the left as in a launcher.
  Widget _grid(int first, int count) => SizedBox(
    width: _l.gridWidth,
    child: Wrap(
      spacing: _l.gap,
      runSpacing: _l.rowGap,
      children: [for (var i = first; i < first + count; i++) _tile(widget.apps[i])],
    ),
  );

  /// The tiles or the chat, one fading into the other.
  Widget _modeSwitch(Widget tiles) => AnimatedSwitcher(
    duration: Motion.of(context, Motion.fold),
    switchInCurve: Motion.enter,
    switchOutCurve: Motion.leave,
    transitionBuilder: (child, t) => FadeTransition(
      opacity: t,
      child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(t), child: child),
    ),
    child: _mode == 0 ? KeyedSubtree(key: const ValueKey('tiles'), child: tiles) : const _ChatSoon(key: ValueKey('chat')),
  );

  /// Room around the grid for the tiles' shadows and their lift.
  static const _air = 14.0;

  /// The pages of tiles across the whole width, with their arrows: placed
  /// from [HomeLayout.gridTop] - [_air].
  Widget _pager() {
    final l = _l;
    Widget arrow(bool next) {
      final shown = next ? _page < _pageCount - 1 : _page > 0;
      return AnimatedOpacity(
        duration: Motion.of(context, Motion.fade),
        opacity: shown ? 1 : 0,
        child: IgnorePointer(
          ignoring: !shown,
          child: RoundButton(next ? 'right' : 'left', size: 28, tooltip: next ? 'Page suivante' : 'Page précédente', onPressed: () => _goTo(_page + (next ? 1 : -1))),
        ),
      );
    }

    // The pages slide across the whole width: tiles and their shadows are
    // never cut before the island's edge. They follow the mouse and the
    // touchpad too, not only a finger.
    final pages = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
        scrollbars: false,
      ),
      child: PageView.builder(
        controller: _pages,
        clipBehavior: Clip.none,
        itemCount: _pageCount,
        onPageChanged: (p) => _set(() => _page = p),
        itemBuilder: (_, p) => Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: _air),
            child: _grid(p * l.perPage, math.min(l.perPage, widget.apps.length - p * l.perPage)),
          ),
        ),
      ),
    );
    final arrowTop = _air + l.gridHeight / 2 - 14;
    return Listener(
      onPointerSignal: _onWheel,
      child: Stack(children: [
        Positioned.fill(child: pages),
        Positioned(left: l.arrowInset, top: arrowTop, child: arrow(false)),
        Positioned(right: l.arrowInset, top: arrowTop, child: arrow(true)),
      ]),
    );
  }

  Widget _dots() => AnimatedOpacity(
    duration: Motion.of(context, Motion.fade),
    opacity: _mode == 0 ? 1 : 0,
    child: PageDots(count: _pageCount, page: _page, onSelect: _goTo),
  );

  Widget _pagerArea() => Positioned(
    left: 0,
    right: 0,
    top: _l.gridTop - _air,
    height: _l.gridHeight + 2 * _air,
    child: _modeSwitch(widget.apps.isEmpty ? const _NoApps() : _pager()),
  );

  // -------------------------------------------------------------------- top

  Widget _top(BuildContext inner) {
    const foot = 10.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _pagerArea(),
        Positioned(left: 4, top: -4, child: _mikkyWidget),
        Positioned(top: HomeLayout.barTop, left: 0, right: 0, child: Center(child: _modes(HomeLayout.barHeight))),
        Positioned(top: HomeLayout.barTop, right: 0, child: _tools()),
        // The dots on the selector's middle line.
        Positioned(left: 0, right: 0, bottom: foot + (EnvironmentSelector.height - PageDots.height) / 2, child: Center(child: _dots())),
        Positioned(right: 12, bottom: foot, child: _environmentSelector(inner)),
      ],
    );
  }

  // ------------------------------------------------------------------ right

  Widget _right(BuildContext inner) {
    final l = _l;
    // The dots halfway between the last row and the modes (from the
    // bottom: a notice above the window may take some of its height).
    final dockTop = l.size.height - HomeLayout.dockBottom - HomeLayout.dockHeight;
    final dotsBottom = l.size.height - (l.gridTop + l.gridHeight + dockTop) / 2 - PageDots.height / 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _pagerArea(),
        Positioned(left: 4, top: -2, child: _mikkyWidget),
        Positioned(top: HomeLayout.barTop + (HomeLayout.barHeight - EnvironmentSelector.height) / 2, left: 0, right: 0, child: Center(child: _environmentSelector(inner))),
        Positioned(top: HomeLayout.barTop, right: 0, child: _tools()),
        Positioned(left: 0, right: 0, bottom: dotsBottom, child: Center(child: _dots())),
        Positioned(left: 0, right: 0, bottom: HomeLayout.dockBottom, child: Center(child: _modes(HomeLayout.dockHeight))),
      ],
    );
  }
}

/// No app yet.
class _NoApps extends StatelessWidget {
  const _NoApps();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Aucun agent pour l’instant', style: uiText(TextSize.body, weight: FontWeight.w500, color: ui.text2)),
        const SizedBox(height: 4),
        Text('Les outils, en haut à droite, lancent Claude ou Codex.', style: uiText(TextSize.small, color: ui.text3)),
      ]),
    );
  }
}

/// The chat, not drawn yet.
class _ChatSoon extends StatelessWidget {
  const _ChatSoon({super.key});

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Center(child: Text('Le chat · à dessiner', style: uiText(TextSize.small, color: ui.text3)));
  }
}

/// The home's window on the boards: the island's color and shadow, flat
/// on the side of the screen's edge (the top for the top, the right for
/// the right), round elsewhere. Drawn as the island: one rounded surface
/// running past that edge, cut there.
class HomeFrame extends StatelessWidget {
  const HomeFrame({super.key, required this.layout, required this.child});

  final HomeLayout layout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final top = layout.isTop, past = layout.radius;
    final r = Radius.circular(layout.radius);
    return ClipRect(
      clipper: _ScreenEdge(top),
      child: SizedBox.fromSize(
        size: layout.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: top ? -past : 0,
              right: top ? 0 : -past,
              bottom: 0,
              child: Surface(color: ui.island, radius: layout.radius, shadows: ui.islandShadow),
            ),
            ClipRRect(borderRadius: top ? BorderRadius.vertical(bottom: r) : BorderRadius.horizontal(left: r), child: child),
          ],
        ),
      ),
    );
  }
}

/// Cuts the side against the screen's edge; the shadow shows elsewhere.
class _ScreenEdge extends CustomClipper<Rect> {
  const _ScreenEdge(this.top);

  final bool top;

  @override
  Rect getClip(Size size) => top ? Rect.fromLTRB(-80, 0, size.width + 80, size.height + 100) : Rect.fromLTRB(-80, -80, size.width, size.height + 100);

  @override
  bool shouldReclip(_ScreenEdge old) => old.top != top;
}
