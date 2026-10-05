import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/app_glyph.dart';
import '../ui/app_tile.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/dot_field.dart';
import '../ui/edge_rail.dart';
import '../ui/environment_selector.dart';
import '../ui/motion.dart';
import '../ui/page_dots.dart';
import '../ui/side.dart';
import '../ui/status.dart';
import '../ui/surface.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';
import 'task_glance.dart';
import 'tools_rail.dart';

/// Where the home lives: the wide island at the top, or the tall one at
/// the right edge.
enum HomePlacement { top, right }

/// The home's measures in one placement (design.md §7): the window, its
/// bar, its pages of tiles and where Mikky sits. Set for the island's real
/// sizes, not scaled from the mockups.
class HomeLayout {
  const HomeLayout._({
    required this.placement,
    required this.size,
    required this.columns,
    required this.rows,
    required this.tile,
    required this.tileWidth,
    required this.gap,
    required this.rowGap,
    required this.gridTop,
    required this.barTop,
    required this.bar,
    required this.foot,
    required this.side,
    required this.mikky,
    required this.mikkyAt,
    double? mikkyIdle,
    Offset? mikkyIdleAt,
  }) : mikkyIdle = mikkyIdle ?? mikky,
       mikkyIdleAt = mikkyIdleAt ?? mikkyAt;

  /// Top: the notch (user, 2026-10-05, « Côte à côte »), 700 × 200 (760 ×
  /// 216 was « trop grand »). On the left, Mikky (96) and the latest task
  /// at work beside him, reaching to the apps (« la partie de gauche plus
  /// étendue »); nothing at work, Mikky alone, bigger (120). On the right,
  /// the other apps as wide tiles, 160 × 42, two by two (three columns
  /// when nothing is at work), arrows on each side when there are more.
  /// Quiet controls: a 32 px bar, a small foot.
  static const top = HomeLayout._(
    placement: HomePlacement.top,
    size: Size(700, 200),
    columns: 2,
    rows: 2,
    tile: 42,
    tileWidth: 160,
    gap: 8,
    rowGap: 8,
    gridTop: taskTop + (taskHeight - 2 * 42 - 8) / 2,
    barTop: 10,
    bar: 32,
    foot: 8,
    side: 12,
    mikky: 96,
    mikkyAt: Offset(10, taskTop + (taskHeight - 96) / 2),
    mikkyIdle: 120,
    mikkyIdleAt: Offset(10, 40),
  );

  /// Right: the home of 2026-10-02 upright (« une version verticale de la
  /// version haut »): 64 px tiles, four rows of two — 8 a page — so
  /// 290 × 408 (`IslandMetrics.right`): the bar, 10, the tiles, 10, the
  /// foot. The notch's idea comes here later (boards « Notch Right »).
  static const right = HomeLayout._(
    placement: HomePlacement.right,
    size: Size(290, 408),
    columns: 2,
    rows: 4,
    tile: 64,
    tileWidth: 64,
    gap: 16,
    rowGap: 10,
    gridTop: 12 + 44 + 10,
    barTop: 12,
    bar: 44,
    foot: 10,
    side: 12,
    mikky: 72,
    mikkyAt: Offset(4, -4),
  );

  /// The task Mikky looks at, in the notch: from the bar's foot, this
  /// high, this far from Mikky; it reaches to [taskEnd] from the apps'
  /// area (190 wide).
  static const taskTop = 46.0, taskHeight = 120.0, taskGap = 8.0, taskEnd = 4.0;

  final HomePlacement placement;
  final Size size;

  /// Tiles per row, rows per page.
  final int columns, rows;

  /// A tile's height, its width (wide in the notch), the gaps.
  final double tile, tileWidth, gap, rowGap;

  /// Where the first row starts.
  final double gridTop;

  /// The bar (modes, tools): from the top, its height.
  final double barTop, bar;

  /// The foot (history, the pages' star, the environment): from the
  /// bottom, from the sides.
  final double foot, side;

  /// Mikky's size and his top left corner; on the notch with nothing at
  /// work, bigger (as `IslandMetrics.top.mikkyListIdle`).
  final double mikky, mikkyIdle;
  final Offset mikkyAt, mikkyIdleAt;

  bool get isTop => placement == HomePlacement.top;

  /// The corners away from the screen's edge.
  double get radius => 30;

  /// A page over the home (an agent's page): the island grows for the
  /// conversation — at the top as wide as the notch, 700 × 380 (user,
  /// 2026-10-05: « garder la largeur »); at the right to the
  /// phone-shaped 344 × 520 (2026-10-02). As `IslandMetrics.page`.
  Size get pageSize => isTop ? const Size(700, 380) : const Size(344, 520);
}

/// One app of the home: one or more agents doing a task (user, 2026-10-02).
/// For now one agent. At the right its tile shows its tool and its state;
/// in the notch its title, [line] and the software it runs in ([app]).
class HomeApp {
  const HomeApp({required this.id, this.name = '', this.brand, this.status, this.line = '', this.app});

  final String id;
  final String name;

  /// The tool it runs with; null: a neutral tile (the boards).
  final Brand? brand;

  /// Its state, in a pastille on the corner; null: nothing.
  final UiStatus? status;

  /// What it does now, or how it ended, in a few words (the notch).
  final String line;

  /// The software it runs in (the notch), if known.
  final AgentApp? app;

  /// [n] neutral apps, for the boards.
  static List<HomeApp> placeholders(int n) => [for (var i = 0; i < n; i++) HomeApp(id: 'app-$i', name: 'Application ${i + 1}')];
}

/// The home, one widget for both placements: Mikky alive, the two modes
/// (apps; chat opens a new chat's page, as an agent's opens — 2026-10-05),
/// the tools on a rail out of the screen's edge, pages of apps (an app:
/// one or more agents doing a task), the history and « Choisir
/// l'environnement ». In the notch at the top, the task Mikky
/// looks at beside him ([watched]). The pages slide sideways: drag
/// (mouse, touchpad), wheel, arrows, dots or ← →. Its own Overlay keeps
/// the menus inside it.
class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    this.layout = HomeLayout.top,
    this.apps = const [],
    this.watched,
    this.onOpen,
    this.onNew,
    this.onHistory,
    this.drawMikky = true,
    this.tools = const [Brand.claude, Brand.codex],
    this.environment = MikkyEnvironment.local,
    this.mikky = MikkyState.idle,
    this.animate = true,
  });

  final HomeLayout layout;

  final List<HomeApp> apps;

  /// The notch: the latest task at work, beside Mikky; null: nothing at
  /// work, a third column of apps takes its place.
  final WatchedTask? watched;

  /// A tile pressed (the watched task too).
  final ValueChanged<HomeApp>? onOpen;

  /// A new task: « + », the tools' rail and the Chat mode open the new
  /// chat's page. Null: cannot launch.
  final VoidCallback? onNew;

  /// The history button, bottom left, given the home's window to open its
  /// sheet in; null: no button.
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

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late MikkyEnvironment _environment = widget.environment;
  int _page = 0;
  final _pages = PageController();
  final _keys = FocusNode(debugLabel: 'home');
  late final _layer = OverlayEntry(builder: _window);

  // The wheel: one page per notch, not a page per event of a long roll.
  double _wheel = 0;
  Duration? _wheelAt;

  HomeLayout get _l => widget.layout;
  bool get _canStart => widget.onNew != null;

  /// The notch with nothing at work: a third column of apps.
  int get _columns => _l.isTop && widget.watched == null ? 3 : _l.columns;
  int get _perPage => _columns * _l.rows;
  double get _gridWidth => _columns * _l.tileWidth + (_columns - 1) * _l.gap;
  double get _gridHeight => _l.rows * _l.tile + (_l.rows - 1) * _l.rowGap;

  /// The apps, then « + » when a task can be started.
  int get _cells => widget.apps.length + (_canStart ? 1 : 0);
  int get _pageCount => math.max(1, (_cells / _perPage).ceil());

  @override
  void didUpdateWidget(HomeView old) {
    super.didUpdateWidget(old);
    // Fewer apps, or a column more or less: no page past the last.
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

  /// « + », a tool or the Chat mode: the new chat's page.
  void _start() => widget.onNew?.call();

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
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
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
    if (event is! PointerScrollEvent || _pageCount < 2) return;
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

  /// Both placements alike: at the top, Mikky, the modes in the middle,
  /// the tools out of the edge; the pages of tiles (in the notch, the
  /// watched task beside Mikky, the apps on the right); at the bottom, the
  /// history on the left, the pages' star, the environment on the right.
  Widget _window(BuildContext inner) {
    final l = _l;
    final top = l.isTop;
    final historyH = top ? _smallButton : 34.0;
    final selectorH = top ? EnvironmentSelector.smallHeight : EnvironmentSelector.height;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The notch: grey dots behind the apps (2026-10-05), whole under
        // them, gone a little into Mikky's part (90 px in was « un tout
        // petit peu trop sur la gauche »).
        if (top) Positioned.fill(child: DotField(solidFrom: _areaLeft + 24, goneAt: _areaLeft - 64)),
        Positioned.fill(child: _tiles()),
        Positioned(left: _mikkyAt.dx, top: _mikkyAt.dy, child: _mikkyWidget),
        Positioned(top: l.barTop, left: 0, right: 0, child: Center(child: _modes())),
        Positioned(top: l.barTop, right: 0, child: _tools()),
        // The star under the apps, on the selector's middle line.
        Positioned(
          left: top ? _gridLeft : 0,
          width: top ? _gridWidth : l.size.width,
          bottom: l.foot + (selectorH - PageDots.height) / 2,
          child: Center(child: _dots()),
        ),
        Positioned(right: l.side, bottom: l.foot, child: _environmentSelector(inner)),
        if (widget.onHistory != null) Positioned(left: l.side, bottom: l.foot + (selectorH - historyH) / 2, child: _history(inner)),
      ],
    );
  }

  /// The notch's small controls: the history, the page arrows.
  static const _smallButton = 24.0, _arrow = 22.0;

  /// The notch's apps: on the right, room on each side for an arrow, 6 px
  /// from them; their area ends 8 px from the edge.
  static const _arrowRoom = _arrow + 6;
  double get _gridLeft => _l.size.width - 8 - _arrowRoom - _gridWidth;
  double get _areaLeft => _gridLeft - _arrowRoom;

  // ------------------------------------------------------------------ parts

  bool get _idle => _l.isTop && widget.watched == null;
  double get _mikkySize => _idle ? _l.mikkyIdle : _l.mikky;
  Offset get _mikkyAt => _idle ? _l.mikkyIdleAt : _l.mikkyAt;

  Widget get _mikkyWidget => widget.drawMikky
      ? MiniMikky(
          size: _mikkySize,
          animate: widget.animate,
          state: widget.mikky,
          badge: false,
          // In the notch he looks at his task, beside him.
          look: _l.isTop && widget.watched != null ? const Offset(1, .3) : null,
        )
      : SizedBox.square(dimension: _mikkySize);

  Widget _modes() => MTabBar(
    mini: true,
    height: _l.bar,
    // The chosen mode in black (2026-10-02): the home's one black, its
    // depth; the arrows stay grey.
    ink: true,
    // The apps are here; the chat is a page of its own.
    selected: 0,
    onChanged: _canStart ? (m) => m == 1 ? _start() : null : null,
    items: const [TabItem('grid', label: 'Applications'), TabItem('chat', label: 'Chat')],
  );

  Widget _tools() => ToolsRail(tools: widget.tools, edge: RailEdge.right, height: _l.bar, onPressed: _canStart ? _start : null);

  Widget _history(BuildContext inner) => _l.isTop
      ? RoundButton('history', size: _smallButton, ghost: true, tooltip: 'Historique', onPressed: () => widget.onHistory!(inner))
      : RoundButton('history', size: 34, tooltip: 'Historique', onPressed: () => widget.onHistory!(inner));

  Widget _environmentSelector(BuildContext inner) => EnvironmentSelector(
    selected: _environment,
    menuWithin: inner,
    small: _l.isTop,
    onChanged: (e) => _set(() => _environment = e),
  );

  /// A square tile (the right): the tool's logo, the state on the corner.
  Widget _tile(HomeApp app) => AppTile(
    key: ValueKey(app.id),
    size: _l.tile,
    label: app.name,
    status: app.status,
    onTap: () => widget.onOpen?.call(app),
    child: app.brand == null ? null : Center(child: BrandLogo(app.brand!, size: (_l.tile * .34).roundToDouble())),
  );

  /// A wide tile (the notch): the software's sign (else the tool's logo),
  /// the title, the line that changes; the state on the corner.
  Widget _card(HomeApp app) {
    final ui = MikkyUi.of(context);
    final sign = app.app != null ? AppGlyph(app.app!, size: 15) : (app.brand == null ? null : BrandLogo(app.brand!, size: 15));
    return AppTile(
      key: ValueKey(app.id),
      size: _l.tile,
      width: _l.tileWidth,
      label: [app.name, ?app.app?.label].join(', '),
      status: app.status,
      onTap: () => widget.onOpen?.call(app),
      child: Padding(
        padding: const EdgeInsets.only(left: 11, right: 12),
        child: Row(children: [
          SizedBox(width: 16, child: Center(child: sign)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text, height: 1.25)),
              if (app.line.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(app.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, color: ui.text3, height: 1.25)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  /// Page [p], always full: its apps, then « + » in the first free
  /// place, then small tokens where apps will come (2026-10-02; in the
  /// notch too, user 2026-10-05).
  Widget _grid(int p) {
    final l = _l, apps = widget.apps;
    final wide = l.isTop ? l.tileWidth : null;
    Widget cell(int i) {
      if (i < apps.length) return l.isTop ? _card(apps[i]) : _tile(apps[i]);
      if (i == apps.length && _canStart) return AddTile(key: const ValueKey('add'), size: l.tile, width: wide, onTap: _start);
      return AppSlot(size: l.tile, width: wide);
    }

    return SizedBox(
      width: _gridWidth,
      child: Wrap(
        spacing: l.gap,
        runSpacing: l.rowGap,
        children: [for (var i = p * _perPage; i < (p + 1) * _perPage; i++) cell(i)],
      ),
    );
  }

  /// The tiles; in the notch, the task Mikky looks at beside them.
  Widget _tiles() {
    final watched = widget.watched;
    return Stack(children: [
      if (_l.isTop && watched != null)
        Positioned(
          left: _l.mikkyAt.dx + _l.mikky + HomeLayout.taskGap,
          top: HomeLayout.taskTop,
          width: _areaLeft - _l.mikkyAt.dx - _l.mikky - HomeLayout.taskGap - HomeLayout.taskEnd,
          height: HomeLayout.taskHeight,
          child: _Watched(task: watched, onTap: () => widget.onOpen?.call(HomeApp(id: watched.id, name: watched.name))),
        ),
      _pagerArea(),
    ]);
  }

  /// Room around the grid for the tiles' shadows and their lift.
  static const _air = 14.0;

  /// The notch's apps fade over this much at their area's edges.
  static const _edgeFade = 20.0;

  /// The pages of tiles with their arrows: at the right across the whole
  /// width, the arrows 18 px from the edges; in the notch over the right
  /// part only, small arrows on each side of the apps.
  Widget _pager() {
    final l = _l;
    final top = l.isTop;
    final arrowSize = top ? _arrow : 28.0;
    Widget arrow(bool next) {
      final shown = next ? _page < _pageCount - 1 : _page > 0;
      return AnimatedOpacity(
        duration: Motion.of(context, Motion.fade),
        opacity: shown ? 1 : 0,
        child: IgnorePointer(
          ignoring: !shown,
          child: RoundButton(
            next ? 'right' : 'left',
            size: arrowSize,
            tooltip: next ? 'Page suivante' : 'Page précédente',
            onPressed: () => _goTo(_page + (next ? 1 : -1)),
          ),
        ),
      );
    }

    // The pages slide across their area: tiles and their shadows are not
    // cut before its edge. They follow the mouse and the touchpad too,
    // not only a finger.
    final pages = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
        scrollbars: false,
      ),
      child: PageView.builder(
        controller: _pages,
        clipBehavior: top ? Clip.hardEdge : Clip.none,
        itemCount: _pageCount,
        onPageChanged: (p) => _set(() => _page = p),
        itemBuilder: (_, p) => Align(
          alignment: Alignment.topCenter,
          child: Padding(padding: const EdgeInsets.only(top: _air), child: _grid(p)),
        ),
      ),
    );
    final arrowTop = _air + _gridHeight / 2 - arrowSize / 2;
    // In the notch, the apps fade out at their area's edges as they slide,
    // instead of being cut there (2026-10-05: « c'est net, pas très beau »);
    // at rest they are whole (the fade lies in the arrows' room).
    final shown = top
        ? ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              final edge = (_edgeFade / rect.width).clamp(0.0, .5);
              return LinearGradient(
                colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                stops: [0, edge, 1 - edge, 1],
              ).createShader(rect);
            },
            child: pages,
          )
        : pages;
    final inset = top ? 0.0 : 18.0;
    return Listener(
      onPointerSignal: _onWheel,
      child: Stack(children: [
        Positioned.fill(child: shown),
        Positioned(left: inset, top: arrowTop, child: arrow(false)),
        Positioned(right: inset, top: arrowTop, child: arrow(true)),
      ]),
    );
  }

  Widget _dots() => PageDots(count: _pageCount, page: _page, onSelect: _goTo);

  Widget _pagerArea() => Positioned(
    left: _l.isTop ? _areaLeft : 0,
    right: _l.isTop ? 8 : 0,
    top: _l.gridTop - _air,
    height: _gridHeight + 2 * _air,
    child: _pager(),
  );
}

/// The task Mikky looks at, beside him in the notch; a click opens it.
class _Watched extends StatelessWidget {
  const _Watched({required this.task, required this.onTap});

  final WatchedTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: task.name,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: TaskGlance(task: task)),
    ),
  );
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
