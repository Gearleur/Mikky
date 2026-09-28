import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../demo/demo_scene.dart';
import '../mikky/mikky_painter.dart';
import '../overlay/overlay_channel.dart';
import '../settings.dart';
import '../theme.dart';
import 'content/focus_views.dart';
import 'content/parts.dart';
import 'island_painter.dart';

/// Size of the transparent window for each edge: big enough for the open
/// island and its shadow, so it never resizes during an animation.
Size windowSizeFor(IslandEdge edge) => switch (edge) {
      IslandEdge.top => const Size(560, 320),
      IslandEdge.right => const Size(400, 700),
    };

/// The shader box goes this far past the screen edge: only the corners
/// away from the edge are rounded.
const _pastEdge = 40.0;
const _awayDelay = Duration(seconds: 3);

const _menuThemeAuto = 1, _menuThemeDark = 2, _menuThemeLight = 3;
const _menuEdgeTop = 4, _menuEdgeRight = 5, _menuQuit = 9;

/// The island with Mikky in it, glued to the top or the right edge.
///
/// The show / hide rules are still the J0 ones (hot zone against the edge,
/// hidden again 3 s after the cursor leaves) until the island state machine
/// of `mikky_engine` takes over. The content is the demo scene.
class IslandView extends StatefulWidget {
  const IslandView({super.key, required this.overlay, required this.settings, required this.program});

  final OverlayChannel overlay;
  final Settings settings;
  final ui.FragmentProgram? program;

  @override
  State<IslandView> createState() => _IslandViewState();
}

class _IslandViewState extends State<IslandView> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  late final ui.FragmentShader? _shader = widget.program?.fragmentShader();
  late IslandMotion _motion = IslandMotion(edge: widget.settings.edge);
  final _mikky = Mikky();
  Duration _lastTick = Duration.zero;
  Offset _cursor = const Offset(-10000, -10000);
  Timer? _awayTimer;

  Widget? _openContent;
  Object? _openContentKey;

  OverlayChannel get _overlay => widget.overlay;
  IslandEdge get _edge => _motion.edge;
  Size get _window => windowSizeFor(_edge);

  @override
  void initState() {
    super.initState();
    _overlay.onCursor = _onCursor;
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlay.onCursor = null;
    _awayTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  MikkyTheme get _theme =>
      MikkyTheme.resolve(widget.settings.theme, WidgetsBinding.instance.platformDispatcher.platformBrightness);

  /// The part of the island on screen, in window coordinates.
  Rect get _islandRect {
    final w = _motion.currentWidth, h = _motion.currentHeight, win = _window;
    return switch (_edge) {
      IslandEdge.top => Rect.fromLTWH(win.width / 2 - w / 2, 0, w, h),
      IslandEdge.right => Rect.fromLTWH(win.width - w, win.height / 2 - h / 2, w, h),
    };
  }

  Rect get _shapeRect {
    final r = _islandRect;
    return switch (_edge) {
      IslandEdge.top => Rect.fromLTRB(r.left, -_pastEdge, r.right, r.bottom),
      IslandEdge.right => Rect.fromLTRB(r.left, r.top, r.right + _pastEdge, r.bottom),
    };
  }

  /// Bumping the cursor into the edge, near the island, brings it out.
  Rect get _hotZone {
    final win = _window;
    return switch (_edge) {
      IslandEdge.top => Rect.fromLTRB(win.width / 2 - 120, -1, win.width / 2 + 120, 10),
      IslandEdge.right => Rect.fromLTRB(win.width - 10, win.height / 2 - 150, win.width + 1, win.height / 2 + 150),
    };
  }

  Offset get _mikkyCenter => _islandRect.topLeft + Offset(_motion.mikkyX, _motion.mikkyY);

  void _setShape(IslandShape shape) {
    if (shape == _motion.shape) return;
    _motion.setShape(shape);
    if (shape == IslandShape.open) _mikky.blink();
    if (shape != IslandShape.compact) _cancelAway();
    _wake();
  }

  void _onCursor(Offset cursor) {
    _cursor = cursor;
    switch (_motion.shape) {
      case IslandShape.hidden:
        if (_hotZone.contains(cursor)) _setShape(IslandShape.compact);
      case IslandShape.compact:
        if (_islandRect.inflate(60).contains(cursor)) {
          _cancelAway();
        } else {
          _awayTimer ??= Timer(_awayDelay, () => _setShape(IslandShape.hidden));
        }
      case IslandShape.open:
        break;
    }
  }

  void _cancelAway() {
    _awayTimer?.cancel();
    _awayTimer = null;
  }

  void _onTapUp(TapUpDetails details) {
    switch (_motion.shape) {
      case IslandShape.hidden:
        break;
      case IslandShape.compact:
        _setShape(IslandShape.open);
      case IslandShape.open:
        final onMikky = (details.localPosition - _mikkyCenter).distance < _motion.mikkyRadius * 1.3;
        if (onMikky) {
          _mikky.boop();
        } else {
          _setShape(IslandShape.compact);
        }
    }
  }

  Future<void> _showMenu() async {
    final s = widget.settings;
    final chosen = await _overlay.showMenu([
      MenuEntry(_menuThemeAuto, 'Thème : automatique', checked: s.theme == ThemeChoice.auto),
      MenuEntry(_menuThemeDark, 'Thème : noir', checked: s.theme == ThemeChoice.dark),
      MenuEntry(_menuThemeLight, 'Thème : blanc', checked: s.theme == ThemeChoice.light),
      const MenuEntry.separator(),
      MenuEntry(_menuEdgeTop, 'Position : en haut', checked: s.edge == IslandEdge.top),
      MenuEntry(_menuEdgeRight, 'Position : à droite', checked: s.edge == IslandEdge.right),
      const MenuEntry.separator(),
      const MenuEntry(_menuQuit, 'Quitter'),
    ]);
    switch (chosen) {
      case _menuQuit:
        _overlay.quit();
      case _menuThemeAuto || _menuThemeDark || _menuThemeLight:
        s.theme = const {
          _menuThemeAuto: ThemeChoice.auto,
          _menuThemeDark: ThemeChoice.dark,
          _menuThemeLight: ThemeChoice.light,
        }[chosen]!;
        unawaited(s.save());
        setState(() {});
      case _menuEdgeTop || _menuEdgeRight:
        final edge = chosen == _menuEdgeTop ? IslandEdge.top : IslandEdge.right;
        if (edge == s.edge) return;
        s.edge = edge;
        unawaited(s.save());
        await _moveTo(edge);
    }
  }

  /// Moves the window to [edge] and opens the island there, so the user
  /// sees where it went.
  Future<void> _moveTo(IslandEdge edge) async {
    _cancelAway();
    _ticker.stop();
    await _overlay.setPlacement(edge, windowSizeFor(edge));
    if (!mounted) return;
    setState(() {
      _motion = IslandMotion(edge: edge)..setShape(IslandShape.open);
    });
    _mikky.blink();
    _wake();
  }

  void _wake() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero ? 1 / 60 : math.min((elapsed - _lastTick).inMicroseconds / 1e6, 1 / 20);
    _lastTick = elapsed;

    _motion.update(dt);
    final c = _mikkyCenter;
    final (lookX, lookY) = Mikky.lookAt(_cursor.dx - c.dx, _cursor.dy - c.dy);
    _mikky.update(dt, lookX: lookX, lookY: lookY);

    // Hidden and still: no more frames until the cursor comes back.
    if (_motion.isGone) _ticker.stop();
    _overlay.setHitRect(_motion.visibility > 0 ? _islandRect : Rect.zero);
    setState(() {});
  }

  late final _actions = FocusActions(onAllow: _mikky.happy, onDeny: () => _mikky.twitch());

  /// Built once per theme and edge, then reused as is on every frame.
  Widget _openContentFor(MikkyTheme theme) {
    final key = (theme, _edge);
    if (key != _openContentKey || _openContent == null) {
      _openContentKey = key;
      final m = _motion.metrics;
      final open = m.open(_motion.layout);
      _openContent = RepaintBoundary(
        child: switch (_edge) {
          IslandEdge.top => FocusWideView(theme: theme, actions: _actions, width: open.width - 104 - 18),
          IslandEdge.right => FocusPortraitView(
              theme: theme,
              actions: _actions,
              size: Size(open.width, open.height),
              mikkyBottom: m.mikkyOpen.y + m.mikkyOpen.radius,
            ),
        },
      );
    }
    return _openContent!;
  }

  /// Content appears with a fade, a slight blur and a small shift.
  Widget _reveal(double opacity, Widget child) {
    if (opacity <= 0) return const SizedBox.shrink();
    final blur = (1 - opacity) * 2.5;
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, (1 - opacity) * 6),
        child: blur > .05 ? ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: child) : child,
      ),
    );
  }

  List<Widget> _compactContent(MikkyTheme theme, Rect rect) {
    final opacity = _motion.compactContentOpacity;
    if (opacity <= 0) return const [];
    final name = Text('Mikky', style: sansStyle(theme, size: _edge == IslandEdge.top ? 13 : 11.5, weight: FontWeight.w600));
    switch (_edge) {
      case IslandEdge.top:
        final slideUp = math.min(0.0, _motion.currentHeight - _motion.metrics.compact.height);
        final top = _motion.metrics.compact.height / 2 - 9 + slideUp;
        return [
          Positioned(left: rect.left + 44, top: top, height: 18, child: Opacity(opacity: opacity, child: Center(child: name))),
          Positioned(
            right: _window.width - rect.right + 14,
            top: top,
            height: 18,
            child: Opacity(
              opacity: opacity,
              child: Center(child: Text('${DemoScene.agents.length}', style: monoStyle(theme, size: 11.5))),
            ),
          ),
        ];
      case IslandEdge.right:
        return [
          Positioned(
            left: rect.left,
            top: rect.top + 62,
            width: _motion.metrics.compact.width,
            height: 18,
            child: Opacity(opacity: opacity, child: Center(child: name)),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_motion.isGone) return const SizedBox.expand();
    final theme = _theme;
    final rect = _islandRect;
    final openOpacity = _motion.openContentOpacity;
    final open = _motion.metrics.open(_motion.layout);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: _onTapUp,
      onSecondaryTapUp: (_) => _showMenu(),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: IslandPainter(
                shader: _shader,
                shape: _shapeRect,
                visible: rect,
                radius: _motion.cornerRadius,
                visibility: _motion.visibility,
                theme: theme,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
          ..._compactContent(theme, rect),
          if (openOpacity > 0)
            switch (_edge) {
              IslandEdge.top => Positioned(left: rect.left + 104, top: 16, child: _reveal(openOpacity, _openContentFor(theme))),
              IslandEdge.right => Positioned(
                  left: rect.left + (rect.width - open.width) / 2,
                  top: rect.top + (rect.height - open.height) / 2,
                  child: _reveal(openOpacity, _openContentFor(theme)),
                ),
            },
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: MikkyPainter(
                  geometry: MikkyGeometry.of(_mikky, _motion.mikkyRadius),
                  center: _mikkyCenter,
                  rim: theme.mikkyRim,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
