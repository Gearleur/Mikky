import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/app_glyph.dart';
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
  });

  /// Top: the notch (user, 2026-10-05, « Côte à côte »), 730 × 216. On the
  /// left, Mikky (84) looking at the latest task at work beside him; on
  /// the right, its other apps as wide tiles, 168 × 44, two by two (three
  /// columns when nothing is at work), arrows on each side when there are
  /// more. Quiet controls: a 32 px bar, a small foot.
  static const top = HomeLayout._(
    placement: HomePlacement.top,
    size: Size(730, 216),
    columns: 2,
    rows: 2,
    tile: 44,
    tileWidth: 168,
    gap: 8,
    rowGap: 8,
    gridTop: taskTop + (taskHeight - 2 * 44 - 8) / 2,
    barTop: 10,
    bar: 32,
    foot: 8,
    side: 12,
    mikky: 84,
    mikkyAt: Offset(10, taskTop + (taskHeight - 84) / 2),
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

  /// The task Mikky looks at, in the notch: from the bar's foot, this high.
  static const taskTop = 50.0, taskHeight = 128.0;

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

  /// Mikky's size and his top left corner.
  final double mikky;
  final Offset mikkyAt;

  bool get isTop => placement == HomePlacement.top;

  /// The corners away from the screen's edge.
  double get radius => 30;

  /// A page over the home (an agent's page): the island grows for the
  /// conversation — at the top 450 × 380; at the right to the
  /// phone-shaped 344 × 520 (2026-10-02). As `IslandMetrics.page`.
  Size get pageSize => isTop ? const Size(450, 380) : const Size(344, 520);
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
/// (apps, chat), the tools on a rail out of the screen's edge, pages of
/// apps (an app: one or more agents doing a task), the history and
/// « Choisir l'environnement ». In the notch at the top, the task Mikky
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

  /// The notch: the latest task at work, beside Mikky; null: nothing at
  /// work, a third column of apps takes its place.
  final WatchedTask? watched;

  /// A tile pressed (the watched task too).
  final ValueChanged<HomeApp>? onOpen;

  /// A new task: the tools' rail and the « + » tile, when
  /// there is no [chat]. Neither: cannot launch.
  final VoidCallback? onNew;

  /// The Chat mode (2026-10-02, the old « Nouvel agent »), given a way
  /// back to the apps (once launched). The tools' rail and « + » come to
  /// it. Null: a placeholder.
  final Widget Function(VoidCallback toApps)? chat;

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

  /// Both placements alike: at the top, Mikky, the modes in the middle,
  /// the tools out of the edge; the pages of tiles (in the notch, the
  /// watched task beside Mikky, the apps on the right); at the bottom, the
  /// history on the left, the pages' star, the environment on the right.
  /// In Chat, its field takes the bottom: the foot fades away.
  Widget _window(BuildContext inner) {
    final l = _l;
    final top = l.isTop;
    final historyH = top ? _smallButton : 34.0;
    final selectorH = top ? EnvironmentSelector.smallHeight : EnvironmentSelector.height;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: _modeSwitch()),
        Positioned(left: l.mikkyAt.dx, top: l.mikkyAt.dy, child: _mikkyWidget),
        Positioned(top: l.barTop, left: 0, right: 0, child: Center(child: _modes())),
        Positioned(top: l.barTop, right: 0, child: _tools()),
        // The star under the apps, on the selector's middle line.
        Positioned(
          left: top ? _gridLeft : 0,
          width: top ? _gridWidth : l.size.width,
          bottom: l.foot + (selectorH - PageDots.height) / 2,
          child: Center(child: _foot(_dots())),
        ),
        Positioned(right: l.side, bottom: l.foot, child: _foot(_environmentSelector(inner))),
        if (widget.onHistory != null) Positioned(left: l.side, bottom: l.foot + (selectorH - historyH) / 2, child: _foot(_history(inner))),
      ],
    );
  }

  /// The notch's small controls: the history, the page arrows.
  static const _smallButton = 24.0, _arrow = 22.0;

  /// The notch's apps: on the right, room on each side for an arrow, 8 px
  /// from them; their area ends 10 px from the edge.
  static const _arrowRoom = _arrow + 8 + 2;
  double get _gridLeft => _l.size.width - 10 - _arrowRoom - _gridWidth;
  double get _areaLeft => _gridLeft - _arrowRoom;

  /// A part of the foot: there on the apps, gone in Chat.
  /// Out with the chat's soft fade; back quickly with the apps.
  Widget _foot(Widget child) => AnimatedOpacity(
    duration: Motion.of(context, _mode == 0 ? const Duration(milliseconds: 120) : Motion.fade),
    opacity: _mode == 0 ? 1 : 0,
    child: IgnorePointer(ignoring: _mode != 0, child: child),
  );

  // ------------------------------------------------------------------ parts

  Widget get _mikkyWidget => widget.drawMikky
      ? MiniMikky(
          size: _l.mikky,
          animate: widget.animate,
          state: widget.mikky,
          badge: false,
          // In the notch he looks at his task, beside him.
          look: _l.isTop && widget.watched != null ? const Offset(1, .3) : null,
        )
      : SizedBox.square(dimension: _l.mikky);

  Widget _modes() => MTabBar(
    mini: true,
    height: _l.bar,
    // The chosen mode in black (2026-10-02): the home's one black, its
    // depth; the arrows stay grey.
    ink: true,
    selected: _mode,
    onChanged: (m) => _set(() => _mode = m),
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

  /// The tiles or the chat, one fading into the other. The chat takes
  /// everything under the bar. To the chat: a soft fade with a slight
  /// zoom, both ways 300 ms (« parfaite »); back to the apps: the chat
  /// gone at once (70 ms), the tiles in 160 ms, no zoom (user, 2026-10-02:
  /// « la transition chat → accueil est trop lente »). An AnimatedSwitcher
  /// gives each child the durations it had when it came in.
  Widget _modeSwitch() {
    final toChat = _mode == 1;
    final watched = widget.watched;
    return AnimatedSwitcher(
      duration: Motion.of(context, toChat ? Motion.fold : _tilesIn),
      reverseDuration: Motion.of(context, toChat ? _chatOut : Motion.fold),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.leave,
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, t) => FadeTransition(
        opacity: t,
        child: child.key == const ValueKey('chat') ? ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(t), child: child) : child,
      ),
      child: _mode == 0
          ? Stack(key: const ValueKey('tiles'), children: [
              if (_l.isTop && watched != null)
                Positioned(
                  left: _l.mikkyAt.dx + _l.mikky + 2,
                  top: HomeLayout.taskTop,
                  width: _areaLeft - _l.mikkyAt.dx - _l.mikky - 2,
                  height: HomeLayout.taskHeight,
                  child: _Watched(task: watched, onTap: () => widget.onOpen?.call(HomeApp(id: watched.id, name: watched.name))),
                ),
              _pagerArea(),
            ])
          : Padding(
              key: const ValueKey('chat'),
              padding: EdgeInsets.only(top: _l.barTop + _l.bar),
              child: widget.chat?.call(() => _set(() => _mode = 0)) ?? const _ChatSoon(),
            ),
    );
  }

  static const _tilesIn = Duration(milliseconds: 160), _chatOut = Duration(milliseconds: 70);

  /// Room around the grid for the tiles' shadows and their lift.
  static const _air = 14.0;

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
    final inset = top ? 2.0 : 18.0;
    return Listener(
      onPointerSignal: _onWheel,
      child: Stack(children: [
        Positioned.fill(child: pages),
        Positioned(left: inset, top: arrowTop, child: arrow(false)),
        Positioned(right: inset, top: arrowTop, child: arrow(true)),
      ]),
    );
  }

  Widget _dots() => AnimatedOpacity(
    duration: Motion.of(context, Motion.fade),
    opacity: _mode == 0 ? 1 : 0,
    child: PageDots(count: _pageCount, page: _page, onSelect: _goTo),
  );

  Widget _pagerArea() => Positioned(
    left: _l.isTop ? _areaLeft : 0,
    right: _l.isTop ? 10 : 0,
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
