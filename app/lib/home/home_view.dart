import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/brand/app_tile.dart';
import '../ui/brand/brand_logo.dart';
import '../ui/content/side.dart';
import '../ui/controls/buttons.dart';
import '../ui/controls/environment_selector.dart';
import '../ui/controls/page_dots.dart';
import '../ui/controls/tabs.dart';
import '../ui/foundation/motion.dart';
import '../ui/foundation/tokens.dart';
import '../ui/pixels/dot_field.dart';
import 'home_app.dart';
import 'home_app_tile.dart';
import 'home_apps_background.dart';
import 'home_layout.dart';
import 'task_glance.dart';
import 'tools_rail.dart';

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
    this.onMenu,
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

  /// Right click on an app or the watched task: its agent's menu.
  final ValueChanged<String>? onMenu;

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

  /// The notch with nothing at work: at the top a third column of apps.
  int get _columns => _l.notch && widget.watched == null ? _l.idleColumns : _l.columns;
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
    final notch = l.notch;
    final historyH = notch ? _smallButton : 34.0;
    final selectorH = notch ? EnvironmentSelector.smallHeight : EnvironmentSelector.height;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (notch)
          Positioned.fill(
            child: HomeAppsBackground(
              axis: l.stacked ? Axis.vertical : Axis.horizontal,
              goneAt: l.stacked ? HomeLayout.taskTop + HomeLayout.taskHeight - _dotsUnderTask : _areaLeft - l.tile,
              solidFrom: l.stacked ? l.gridTop + l.tile : _areaLeft + l.tileWidth,
            ),
          ),
        // The notch: grey dots behind the apps (2026-10-05), whole under
        // them, gone a little into Mikky's part (90 px in was « un tout
        // petit peu trop sur la gauche »). Upright, they rise from under
        // the task, fading towards it.
        if (notch && !l.stacked)
          Positioned.fill(
            child: DotField(solidFrom: _areaLeft + 24, goneAt: _areaLeft - 64),
          ),
        // Nothing at work, they fill the task's place too, beside Mikky
        // asleep, and fade towards him, as at the top.
        if (l.stacked)
          _idle
              ? Positioned(
                  left: 0,
                  right: 0,
                  top: l.barTop + l.bar - _dotsUnderTask,
                  bottom: 0,
                  child: DotField(solidFrom: _taskLeft + 24, goneAt: l.mikkyAt.dx + l.mikky / 2),
                )
              : const Positioned(
                  left: 0,
                  right: 0,
                  top: HomeLayout.taskTop + HomeLayout.taskHeight - _dotsUnderTask,
                  bottom: 0,
                  child: DotField(solidFrom: 0, goneAt: -1),
                ),
        Positioned.fill(child: _tiles()),
        Positioned(left: _mikkyAt.dx, top: _mikkyAt.dy, child: _mikkyWidget),
        Positioned(
          top: l.barTop,
          left: 0,
          right: 0,
          child: Center(child: _modes()),
        ),
        Positioned(top: l.barTop, right: 0, child: _tools()),
        // The star under the apps, on the selector's middle line.
        Positioned(
          left: notch ? _gridLeft : 0,
          width: notch ? _gridWidth : l.size.width,
          bottom: l.foot + (selectorH - PageDots.height) / 2,
          child: Center(child: _halo(_dots())),
        ),
        Positioned(
          right: notch ? l.side - _haloPad.horizontal / 2 : l.side,
          bottom: notch ? l.foot - _haloPad.vertical / 2 : l.foot,
          child: _halo(_environmentSelector(inner)),
        ),
        if (widget.onHistory != null)
          Positioned(left: l.side, bottom: l.foot + (selectorH - historyH) / 2, child: _history(inner)),
      ],
    );
  }

  /// In the notch, a light blur around the pages' dots and the
  /// environment, over the dots behind the apps (2026-10-05: « un petit
  /// effet de flou, vraiment léger, juste autour de ces éléments »).
  static const _haloPad = EdgeInsets.symmetric(horizontal: 6, vertical: 3);

  Widget _halo(Widget child) {
    if (!_l.notch) return child;
    final ui = MikkyUi.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
        child: DecoratedBox(
          decoration: BoxDecoration(color: ui.island.withValues(alpha: .5)),
          child: Padding(padding: _haloPad, child: child),
        ),
      ),
    );
  }

  /// The notch's small controls: the history, the page arrows.
  static const _smallButton = 24.0, _arrow = HomeLayout.arrow;

  /// The notch's apps: on the right (at the top) or under the task
  /// (upright), room on each side for an arrow, 6 px from them; their
  /// area ends 8 px from the edge.
  double get _gridLeft => _l.size.width - 8 - HomeLayout.arrowRoom - _gridWidth;
  double get _areaLeft => _gridLeft - HomeLayout.arrowRoom;

  /// Upright, the dots start this far up into the task's foot.
  static const _dotsUnderTask = 24.0;

  /// The task Mikky looks at starts this far from the left, beside him.
  double get _taskLeft => _l.mikkyAt.dx + _l.mikky + HomeLayout.taskGap;

  // ------------------------------------------------------------------ parts

  bool get _idle => _l.notch && widget.watched == null;
  double get _mikkySize => _idle ? _l.mikkyIdle : _l.mikky;
  Offset get _mikkyAt => _idle ? _l.mikkyIdleAt : _l.mikkyAt;

  Widget get _mikkyWidget => widget.drawMikky
      ? MiniMikky(
          size: _mikkySize,
          animate: widget.animate,
          state: widget.mikky,
          badge: false,
          // In the notch he looks at his task, beside him.
          look: _l.notch && widget.watched != null ? const Offset(1, .3) : null,
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
    items: const [
      TabItem('grid', label: 'Applications'),
      TabItem('chat', label: 'Chat'),
    ],
  );

  Widget _tools() => ToolsRail(tools: widget.tools, height: _l.bar, onPressed: _canStart ? _start : null);

  Widget _history(BuildContext inner) => _l.notch
      ? RoundButton(
          'history',
          size: _smallButton,
          ghost: true,
          tooltip: 'Historique',
          onPressed: () => widget.onHistory!(inner),
        )
      : RoundButton('history', size: 34, tooltip: 'Historique', onPressed: () => widget.onHistory!(inner));

  Widget _environmentSelector(BuildContext inner) => EnvironmentSelector(
    selected: _environment,
    menuWithin: inner,
    small: _l.notch,
    onChanged: (e) => _set(() => _environment = e),
  );

  /// Page [p], always full: its apps, then « + » in the first free
  /// place, then small tokens where apps will come (2026-10-02; in the
  /// notch too, user 2026-10-05).
  Widget _grid(int p) {
    final l = _l, apps = widget.apps;
    final wide = l.notch ? l.tileWidth : null;
    Widget cell(int i) {
      if (i < apps.length) {
        final app = apps[i];
        return HomeAppTile(
          key: ValueKey(app.id),
          app: app,
          size: l.tile,
          width: wide,
          onTap: () => widget.onOpen?.call(app),
          onMenu: widget.onMenu == null ? null : () => widget.onMenu!(app.id),
        );
      }
      if (i == apps.length && _canStart) {
        return AddTile(key: const ValueKey('add'), size: l.tile, width: wide, onTap: _start);
      }
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

  /// The tiles; in the notch, the task Mikky looks at beside him: at the
  /// top up to the apps, upright over them, to the side's margin.
  Widget _tiles() {
    final watched = widget.watched, l = _l;
    final taskLeft = _taskLeft;
    final taskRight = l.stacked ? l.size.width - l.side : _areaLeft - HomeLayout.taskEnd;
    return Stack(
      children: [
        if (l.notch && watched != null)
          Positioned(
            left: taskLeft,
            top: HomeLayout.taskTop,
            width: taskRight - taskLeft,
            height: HomeLayout.taskHeight,
            child: _Watched(
              task: watched,
              onTap: () => widget.onOpen?.call(HomeApp(id: watched.id, name: watched.name)),
              onMenu: widget.onMenu == null ? null : () => widget.onMenu!(watched.id),
            ),
          ),
        _pagerArea(),
      ],
    );
  }

  /// Room around the grid for the tiles' shadows and their lift.
  static const _air = 14.0;

  /// The notch's apps fade over this much at their area's edges.
  static const _edgeFade = 20.0;

  /// The pages of tiles with their arrows: in the old home at the right
  /// across the whole width, the arrows 18 px from the edges; in the notch
  /// over the apps' part only, small arrows on each side of the apps.
  Widget _pager() {
    final l = _l;
    final top = l.notch;
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
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
        scrollbars: false,
      ),
      child: PageView.builder(
        controller: _pages,
        clipBehavior: top ? Clip.hardEdge : Clip.none,
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
      child: Stack(
        children: [
          Positioned.fill(child: shown),
          Positioned(left: inset, top: arrowTop, child: arrow(false)),
          Positioned(right: inset, top: arrowTop, child: arrow(true)),
        ],
      ),
    );
  }

  Widget _dots() => PageDots(count: _pageCount, page: _page, onSelect: _goTo);

  Widget _pagerArea() => Positioned(
    left: _l.notch ? _areaLeft : 0,
    right: _l.notch ? 8 : 0,
    top: _l.gridTop - _air,
    height: _gridHeight + 2 * _air,
    child: _pager(),
  );
}

/// The task Mikky looks at, beside him in the notch; a click opens it.
class _Watched extends StatelessWidget {
  const _Watched({required this.task, required this.onTap, this.onMenu});

  final WatchedTask task;
  final VoidCallback onTap;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: task.name,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onSecondaryTapUp: onMenu == null ? null : (_) => onMenu!(),
        child: TaskGlance(task: task),
      ),
    ),
  );
}
