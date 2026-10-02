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
    required this.foot,
    required this.side,
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
    foot: 10,
    side: 12,
  );

  /// Right: as the top (user, 2026-10-02: « trop grosse », « les mêmes
  /// proportions que la version haut », 8 apps): 380 × 260
  /// (`IslandMetrics.right`), two rows of four 64 px tiles; 380 wide, not
  /// 344, for the arrows beside them. Before: 344 × 520, 2 × 3 of 104 px.
  static const right = HomeLayout._(
    placement: HomePlacement.right,
    size: Size(380, 260),
    radius: 30,
    columns: 4,
    rows: 2,
    tile: 64,
    gap: 14,
    rowGap: 10,
    gridTop: barTop + barHeight + 10,
    arrowInset: 8,
    foot: 10,
    side: 12,
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

  /// The foot (history, the pages' star, the environment): from the
  /// bottom, from the sides.
  final double foot, side;

  bool get isTop => placement == HomePlacement.top;
  int get perPage => columns * rows;
  double get gridWidth => columns * tile + (columns - 1) * gap;
  double get gridHeight => rows * tile + (rows - 1) * rowGap;

  /// The bar at the top: Mikky, the modes, the tools.
  static const barTop = 12.0, barHeight = 44.0;
  double get mikkySize => 72;

  /// A page over the home (an agent's Suivi / Chat): the island grows for
  /// the conversation — at the top a little, 450 × 380; at the right to a
  /// phone's shape, 380 × 520 (2026-10-02). As `IslandMetrics.page`.
  Size get pageSize => isTop ? const Size(450, 380) : const Size(380, 520);
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
    this.onNew,
    this.chat,
    this.onHistory,
    this.drawMikky = true,
    this.tools = const [Brand.claude, Brand.codex],
    this.environment = MikkyEnvironment.local,
    this.mikky = MikkyState.idle,
    this.animate = true,
    this.inChat = false,
  });

  final HomeLayout layout;

  final List<HomeApp> apps;

  /// A tile pressed.
  final ValueChanged<HomeApp>? onOpen;

  /// A new task: the tools' rail and the « + » tile, when there is no
  /// [chat]. Neither: cannot launch (no « + »).
  final VoidCallback? onNew;

  /// The Chat mode (2026-10-02, the old « Nouvel agent »), given a way
  /// back to the apps (once launched). The tools' rail and « + » come to
  /// it. Null: a placeholder.
  final Widget Function(VoidCallback toApps)? chat;

  /// The history button, bottom left (trial on the Composants board,
  /// 2026-10-02), given the home's window to open its sheet in; null: no
  /// button.
  final ValueChanged<BuildContext>? onHistory;

  /// False: the island draws its own Mikky in his place (the app: he comes
  /// from the closed island to this spot, in the state of his agent).
  final bool drawMikky;
  final List<Brand> tools;
  final MikkyEnvironment environment;

  /// Mikky's state: the agent he follows.
  final MikkyState mikky;

  /// False: Mikky still (goldens).
  final bool animate;

  /// Opens on the Chat (the boards).
  final bool inChat;


  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late MikkyEnvironment _environment = widget.environment;
  late int _mode = widget.inChat ? 1 : 0;
  int _page = 0;
  final _pages = PageController();
  final _keys = FocusNode(debugLabel: 'home');
  late final _layer = OverlayEntry(builder: _window);

  // The wheel: one page per notch, not a page per event of a long roll.
  double _wheel = 0;
  Duration? _wheelAt;

  HomeLayout get _l => widget.layout;
  bool get _canStart => widget.chat != null || widget.onNew != null;

  /// The apps, then « + » when a task can be started.
  int get _cells => widget.apps.length + (_canStart ? 1 : 0);
  int get _pageCount => math.max(1, (_cells / _l.perPage).ceil());

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

  /// « + » or a tool: the Chat, to say what to do.
  void _start() {
    if (widget.chat != null) {
      _set(() => _mode = 1);
    } else {
      widget.onNew?.call();
    }
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

  /// Both placements alike (2026-10-02): at the top, Mikky, the modes in
  /// the middle, the tools out of the edge; the pages of tiles; at the
  /// bottom, the history on the left, the pages' star in the middle, the
  /// environment on the right (it unfolds up, straight). In Chat, its
  /// field takes the bottom: the foot fades away.
  Widget _window(BuildContext inner) {
    final l = _l;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: _modeSwitch()),
        Positioned(left: 4, top: -4, child: _mikkyWidget),
        Positioned(top: HomeLayout.barTop, left: 0, right: 0, child: Center(child: _modes(HomeLayout.barHeight))),
        Positioned(top: HomeLayout.barTop, right: 0, child: _tools()),
        // The star on the selector's middle line.
        Positioned(left: 0, right: 0, bottom: l.foot + (EnvironmentSelector.height - PageDots.height) / 2, child: Center(child: _foot(_dots()))),
        Positioned(right: l.side, bottom: l.foot, child: _foot(_environmentSelector(inner))),
        if (widget.onHistory != null) Positioned(left: l.side, bottom: l.foot + (EnvironmentSelector.height - 34) / 2, child: _foot(_history(inner))),
      ],
    );
  }

  /// A part of the foot: there on the apps, gone in Chat.
  Widget _foot(Widget child) => AnimatedOpacity(
    duration: Motion.of(context, Motion.fade),
    opacity: _mode == 0 ? 1 : 0,
    child: IgnorePointer(ignoring: _mode != 0, child: child),
  );

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

  Widget _tools() => ToolsRail(tools: widget.tools, edge: RailEdge.right, height: HomeLayout.barHeight, onPressed: _canStart ? _start : null);

  Widget _history(BuildContext inner) => RoundButton('history', size: 34, tooltip: 'Historique', onPressed: () => widget.onHistory!(inner));

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

  /// Page [p], always full: its apps, then « + » in the first free
  /// place, then small tokens where apps will come (2026-10-02).
  Widget _grid(int p) {
    final l = _l, apps = widget.apps;
    Widget cell(int i) {
      if (i < apps.length) return _tile(apps[i]);
      if (i == apps.length && _canStart) return AddTile(key: const ValueKey('add'), size: l.tile, onTap: _start);
      return AppSlot(size: l.tile);
    }

    return SizedBox(
      width: l.gridWidth,
      child: Wrap(
        spacing: l.gap,
        runSpacing: l.rowGap,
        children: [for (var i = p * l.perPage; i < (p + 1) * l.perPage; i++) cell(i)],
      ),
    );
  }

  /// The tiles or the chat, one fading into the other. The chat takes
  /// everything under the bar.
  Widget _modeSwitch() => AnimatedSwitcher(
    duration: Motion.of(context, Motion.fold),
    switchInCurve: Motion.enter,
    switchOutCurve: Motion.leave,
    layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
    transitionBuilder: (child, t) => FadeTransition(
      opacity: t,
      child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(t), child: child),
    ),
    child: _mode == 0
        ? Stack(key: const ValueKey('tiles'), children: [_pagerArea()])
        : Padding(
            key: const ValueKey('chat'),
            padding: const EdgeInsets.only(top: HomeLayout.barTop + HomeLayout.barHeight),
            child: widget.chat?.call(() => _set(() => _mode = 0)) ?? const _ChatSoon(),
          ),
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
            child: _grid(p),
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
    child: _pager(),
  );
}

/// The chat, not drawn yet.
class _ChatSoon extends StatelessWidget {
  const _ChatSoon();

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
  const HomeFrame({super.key, required this.layout, required this.child, this.size});

  final HomeLayout layout;
  final Widget child;

  /// Another size than the home's (a page: [HomeLayout.pageSize]).
  final Size? size;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final top = layout.isTop, past = layout.radius;
    final r = Radius.circular(layout.radius);
    return ClipRect(
      clipper: _ScreenEdge(top),
      child: SizedBox.fromSize(
        size: size ?? layout.size,
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
            Positioned.fill(child: ClipRRect(borderRadius: top ? BorderRadius.vertical(bottom: r) : BorderRadius.horizontal(left: r), child: child)),
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
