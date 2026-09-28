import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../overlay/overlay_channel.dart';
import '../settings.dart';
import '../theme.dart';
import 'island_painter.dart';

/// The island with Mikky in it.
///
/// The show / hide rules are still the J0 ones (hot zone at the top center,
/// hidden again 3 s after the cursor leaves) until the island state machine
/// of `mikky_engine` takes over.
class IslandView extends StatefulWidget {
  const IslandView({super.key, required this.settings, required this.program});

  final Settings settings;
  final ui.FragmentProgram? program;

  @override
  State<IslandView> createState() => _IslandViewState();
}

/// Same as the native window width (`windows/runner/main.cpp`).
const _windowWidth = 560.0;
const _centerX = _windowWidth / 2;
const _hotZone = Rect.fromLTRB(_centerX - 120, -1, _centerX + 120, 10);
const _awayDelay = Duration(seconds: 3);

const _menuThemeAuto = 1, _menuThemeDark = 2, _menuThemeLight = 3, _menuQuit = 9;

class _IslandViewState extends State<IslandView> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final OverlayChannel _overlay;
  late final Ticker _ticker;
  late final ui.FragmentShader? _shader = widget.program?.fragmentShader();
  final _motion = IslandMotion();
  final _mikky = Mikky();
  Duration _lastTick = Duration.zero;
  Offset _cursor = const Offset(-10000, -10000);
  Timer? _awayTimer;

  @override
  void initState() {
    super.initState();
    _overlay = OverlayChannel(onCursor: _onCursor);
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _awayTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  MikkyTheme get _theme =>
      MikkyTheme.resolve(widget.settings.theme, WidgetsBinding.instance.platformDispatcher.platformBrightness);

  Rect get _islandRect {
    final w = _motion.currentWidth;
    return Rect.fromLTRB(_centerX - w / 2, 0, _centerX + w / 2, _motion.currentHeight);
  }

  Offset get _mikkyCenter => Offset(_islandRect.left + _motion.mikkyX, _motion.mikkyY);

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

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kSecondaryMouseButton != 0) {
      _showMenu();
      return;
    }
    switch (_motion.shape) {
      case IslandShape.hidden:
        break;
      case IslandShape.compact:
        _setShape(IslandShape.open);
      case IslandShape.open:
        final onMikky = (event.localPosition - _mikkyCenter).distance < _motion.mikkyRadius * 1.3;
        if (onMikky) {
          _mikky.boop();
        } else {
          _setShape(IslandShape.compact);
        }
    }
  }

  Future<void> _showMenu() async {
    final theme = widget.settings.theme;
    final chosen = await _overlay.showMenu([
      MenuEntry(_menuThemeAuto, 'Thème : automatique', checked: theme == ThemeChoice.auto),
      MenuEntry(_menuThemeDark, 'Thème : noir', checked: theme == ThemeChoice.dark),
      MenuEntry(_menuThemeLight, 'Thème : blanc', checked: theme == ThemeChoice.light),
      const MenuEntry.separator(),
      const MenuEntry(_menuQuit, 'Quitter'),
    ]);
    final newTheme = switch (chosen) {
      _menuThemeAuto => ThemeChoice.auto,
      _menuThemeDark => ThemeChoice.dark,
      _menuThemeLight => ThemeChoice.light,
      _ => null,
    };
    if (chosen == _menuQuit) {
      _overlay.quit();
    } else if (newTheme != null && newTheme != theme) {
      widget.settings.theme = newTheme;
      unawaited(widget.settings.save());
      setState(() {});
    }
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

  @override
  Widget build(BuildContext context) {
    if (_motion.isGone) return const SizedBox.expand();
    final theme = _theme;
    final rect = _islandRect;
    final slideUp = math.min(0.0, _motion.currentHeight - IslandMotion.compactHeight);
    return Listener(
      onPointerDown: _onPointerDown,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: IslandPainter(
              shader: _shader,
              motion: _motion,
              centerX: _centerX,
              theme: theme,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            ),
          ),
          Positioned(
            left: rect.left + 44,
            top: IslandMotion.compactHeight / 2 - 9 + slideUp,
            height: 18,
            child: Opacity(
              opacity: _motion.compactContentOpacity,
              child: Center(
                child: Text(
                  'Mikky',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                    letterSpacing: -.13,
                    color: theme.foreground,
                  ),
                ),
              ),
            ),
          ),
          CustomPaint(
            size: Size.infinite,
            painter: MikkyPainter(
              geometry: MikkyGeometry.of(_mikky, _motion.mikkyRadius),
              center: _mikkyCenter,
              rim: theme.mikkyRim,
            ),
          ),
        ],
      ),
    );
  }
}
