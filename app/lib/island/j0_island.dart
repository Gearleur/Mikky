import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../overlay/overlay_channel.dart';

/// Milestone J0 stand-in for the island: a plain rounded rectangle and two
/// eyes that follow the cursor. It only exists to validate the overlay
/// (transparency, click-through, global mouse, 0 % CPU when hidden) and will
/// be replaced by `mikky_engine` + the shader from J1 on.
class J0Island extends StatefulWidget {
  const J0Island({super.key});

  @override
  State<J0Island> createState() => _J0IslandState();
}

enum _Mode { hidden, compact, open }

const _windowWidth = 560.0;
const _centerX = _windowWidth / 2;
const _hotZone = Rect.fromLTRB(_centerX - 120, -1, _centerX + 120, 10);
const _awayDelay = Duration(seconds: 3);

class _J0IslandState extends State<J0Island> with SingleTickerProviderStateMixin {
  late final OverlayChannel _overlay;
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;

  _Mode _mode = _Mode.hidden;
  final _width = _Spring(120);
  final _height = _Spring(0);
  Offset _gaze = Offset.zero;
  Offset _gazeTarget = Offset.zero;
  Timer? _awayTimer;

  Rect get _islandRect =>
      Rect.fromLTRB(_centerX - _width.value / 2, 0, _centerX + _width.value / 2, _height.value);

  bool get _visible => _height.value > 0.5;

  Offset get _mikkyCenter => Offset(_islandRect.left + 24, math.min(_height.value, 36) / 2);

  @override
  void initState() {
    super.initState();
    _overlay = OverlayChannel(onCursor: _onCursor);
  }

  @override
  void dispose() {
    _awayTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _setMode(_Mode mode) {
    _mode = mode;
    final (w, h) = switch (mode) {
      _Mode.hidden => (120.0, 0.0),
      _Mode.compact => (186.0, 36.0),
      _Mode.open => (430.0, 178.0),
    };
    _width.target = w;
    _height.target = h;
    if (mode != _Mode.compact) _cancelAway();
    _wake();
  }

  void _onCursor(Offset cursor) {
    switch (_mode) {
      case _Mode.hidden:
        // Nothing is drawn: no frame, just a cheap hit test.
        if (_hotZone.contains(cursor)) _setMode(_Mode.compact);
        return;
      case _Mode.compact:
        if (_islandRect.inflate(60).contains(cursor)) {
          _cancelAway();
        } else {
          _awayTimer ??= Timer(_awayDelay, () => _setMode(_Mode.hidden));
        }
      case _Mode.open:
        break;
    }
    final d = cursor - _mikkyCenter;
    _gazeTarget = Offset(_tanh(d.dx / 260), _tanh(d.dy / 200));
    _wake();
  }

  void _cancelAway() {
    _awayTimer?.cancel();
    _awayTimer = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kSecondaryMouseButton != 0) {
      _overlay.quit();
      return;
    }
    _setMode(_mode == _Mode.open ? _Mode.compact : _Mode.open);
  }

  void _wake() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : math.min((elapsed - _lastTick).inMicroseconds / 1e6, 1 / 20);
    _lastTick = elapsed;

    _width.step(dt);
    _height.step(dt);
    final k = 1 - math.exp(-dt * 12);
    _gaze += (_gazeTarget - _gaze) * k;

    final gazeSettled = (_gazeTarget - _gaze).distance < 0.002;
    if (_width.settled && _height.settled && gazeSettled) {
      _gaze = _gazeTarget;
      _ticker.stop();
    }
    _overlay.setHitRect(_visible ? _islandRect : Rect.zero);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      behavior: HitTestBehavior.translucent,
      child: CustomPaint(
        size: Size.infinite,
        painter: _J0Painter(
          rect: _visible ? _islandRect : null,
          mikky: _mikkyCenter,
          gaze: _gaze,
        ),
      ),
    );
  }
}

double _tanh(double x) {
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// Damped spring with the island's "dry" settings from the spec (§3).
class _Spring {
  _Spring(this.value) : target = value;

  static const stiffness = 210.0;
  static const dampingRatio = 0.74;

  double value;
  double target;
  double velocity = 0;

  bool get settled => (value - target).abs() < 0.05 && velocity.abs() < 0.5;

  void step(double dt) {
    const damping = 2 * dampingRatio * 14.491376746189438; // sqrt(210)
    const substeps = 4;
    final h = dt / substeps;
    for (var i = 0; i < substeps; i++) {
      velocity += (-stiffness * (value - target) - damping * velocity) * h;
      value += velocity * h;
    }
    if (settled) {
      value = target;
      velocity = 0;
    }
  }
}

class _J0Painter extends CustomPainter {
  _J0Painter({required this.rect, required this.mikky, required this.gaze});

  final Rect? rect;
  final Offset mikky;
  final Offset gaze;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect;
    if (r == null) return;
    final t = ((r.height - 36) / (178 - 36)).clamp(0.0, 1.0);
    final radius = 18 + (30 - 18) * t;
    // The top edge sits above the screen: only the bottom corners show.
    final shape = RRect.fromLTRBR(r.left, -radius, r.right, r.bottom, Radius.circular(radius));
    canvas.drawRRect(shape, Paint()..color = const Color(0xFF070708));
    canvas.drawRRect(
      shape.deflate(0.65),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = const Color(0x1FFFFFFF),
    );

    final eye = Paint()..color = const Color(0xFFF7F7F7);
    final look = Offset(gaze.dx * 3, gaze.dy * 2.5);
    for (final side in const [-1.0, 1.0]) {
      final c = mikky + Offset(side * 5, 0) + look;
      if (c.dy + 4 > r.bottom) continue;
      canvas.drawOval(Rect.fromCenter(center: c, width: 4.5, height: 9), eye);
    }
  }

  @override
  bool shouldRepaint(_J0Painter old) => old.rect != rect || old.gaze != gaze || old.mikky != mikky;
}
