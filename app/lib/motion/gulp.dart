import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import '../ui/motion.dart';
import '../ui/pixel_fx.dart';
import '../ui/tokens.dart';

/// Mikky with his mouth wide open, breathing a file in, like Kirby
/// (2026-10-08, the user: « déforme Mikky pour qu'il ressemble plus à
/// Kirby, dans la forme aussi le mouvement, il se penche en arrière » —
/// four proposals, still poses that live in a loop, to choose from before
/// any animation). The one time he has a mouth.
///
/// His real drawing, bent from outside: he leans back from the ground, his
/// body stretches toward his mouth and packs in behind, the wind sweeps his
/// ears back, and he wobbles like jelly. Every part moves a little after
/// the one before it (body, then mouth, then ears): overlapping action,
/// for a soft, springy feel.
enum GulpAir {
  /// Thin strokes rushing into his mouth (a manga's speed lines).
  lines,

  /// Streaks of pixels, in our signature blue (our pixel direction).
  pixels,

  /// A whirl of dashes turning into his mouth.
  whirl,
}

class GulpPose {
  const GulpPose({
    required this.name,
    required this.note,
    required this.toward,
    this.yaw = 0,
    this.mouthAt = .4,
    this.mouthSpan = 1.0,
    this.mouthDepth = .8,
    this.stretch = .25,
    this.squash = .1,
    this.lean = -.2,
    this.puff = 0,
    this.earSweep = .2,
    this.ears = 0,
    this.eyes = EyeShape.oval,
    this.eyeLift = .1,
    this.eyeScale = 1,
    this.wobble = .03,
    this.period = 1.2,
    this.air = GulpAir.lines,
    this.spread = .6,
    this.file = false,
    this.mouthX = 0,
    this.pitch = 0,
    this.mouthShape = GulpMouth.oval,
  });

  final String name, note;

  /// Where his mouth opens, an angle (radians; 0: to the right, π/2: down,
  /// toward the viewer for a front view).
  final double toward;

  /// His head turned (the eye sphere).
  final double yaw;

  /// The mouth's center, from his center toward [toward], in his radius;
  /// its size across and along [toward], in his radius.
  final double mouthAt, mouthSpan, mouthDepth;

  /// His body pulled toward his mouth, and packed in on the other side.
  final double stretch, squash;

  /// Leaning back from the ground (radians; < 0: to the left).
  final double lean;

  /// Bigger and rounder, full of air.
  final double puff;

  /// His ears swept back by the wind; raised (> 0) or lowered (< 0).
  final double earSweep, ears;

  final EyeShape eyes;

  /// His eyes pushed up and back by the mouth, in his radius.
  final double eyeLift, eyeScale;

  /// How much he wobbles (in his radius), and the loop (seconds).
  final double wobble, period;

  final GulpAir air;

  /// How wide the air comes from, around [toward] (radians; π: all round).
  final double spread;

  /// A file pulled toward his mouth.
  final bool file;

  /// The mouth moved sideways (his head turned), in his radius.
  final double mouthX;

  /// His face raised on the ball (> 0: he looks up, leaning back).
  final double pitch;

  final GulpMouth mouthShape;
}

/// The mouth's outline, always wider than tall (2026-10-08, the user:
/// « pas forcément ronde mais ovale de façon horizontale »).
enum GulpMouth {
  /// A wide oval.
  oval,

  /// The top lip almost flat, the bottom deep and round, like Kirby's.
  dee,

  /// A wide, soft rectangle: a shout.
  soft,
}

abstract final class GulpPoses {
  static const all = [front];

  /// Kirby's front view: a wide mouth in his lower body, the jaw dropped a
  /// little, the air coming from all around. He stays a ball.
  static const front = GulpPose(
    name: 'De face',
    note: 'Celle que tu as gardée, la bouche en ovale horizontal : une grande bouche dans le bas du corps, les yeux poussés en haut, il reste une boule qui se penche à peine en arrière. L’air arrive de partout.',
    toward: math.pi / 2,
    mouthAt: .36,
    mouthSpan: 1.34,
    mouthDepth: .82,
    stretch: .14,
    squash: .08,
    lean: -.1,
    puff: .3,
    earSweep: 0,
    ears: .35,
    eyeLift: .16,
    eyeScale: 1.08,
    wobble: .022,
    period: 1.15,
    spread: math.pi,
  );
}

/// [pose] living in a loop, at 60 images a second while it shows (still
/// when Windows asks for fewer animations, and in the test pictures).
class GulpLive extends StatefulWidget {
  const GulpLive(this.pose, {super.key, this.size = const Size(260, 210), this.radius = 44, this.frozenAt = .2});

  final GulpPose pose;
  final Size size;
  final double radius;

  /// Where in the loop (0 to 1) it stands still.
  final double frozenAt;

  @override
  State<GulpLive> createState() => _GulpLiveState();
}

class _GulpLiveState extends State<GulpLive> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => _t.value = elapsed.inMicroseconds / 1e6);
  late final ValueNotifier<double> _t = ValueNotifier(widget.frozenAt * widget.pose.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = Motion.loops(context);
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
      _t.value = widget.frozenAt * widget.pose.period;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mui = MikkyUi.of(context);
    final theme = mui.isLight ? MikkyTheme.light : MikkyTheme.dark;
    return RepaintBoundary(
      child: Container(
        width: widget.size.width,
        height: widget.size.height,
        color: mui.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708),
        child: CustomPaint(painter: GulpPainter(widget.pose, _t, theme, widget.radius)),
      ),
    );
  }
}

class GulpPainter extends CustomPainter {
  GulpPainter(this.pose, this.time, this.theme, this.radius) : super(repaint: time);

  final GulpPose pose;
  final ValueListenable<double> time;
  final MikkyTheme theme;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose;
    final r = radius;
    final t = time.value;
    final ph = 2 * math.pi * t / p.period;
    // Overlapping action: the body breathes, the mouth a little ahead, the
    // lean and the ears a little behind.
    final breath = math.sin(ph);
    final stretch = p.stretch * (1 + .16 * breath);
    final squash = p.squash * (1 + .12 * breath);
    final lean = p.lean * (1 + .1 * math.sin(ph - .7));
    final open = 1 + .08 * math.sin(ph + .9);
    final sweep = p.earSweep * (1 + .3 * math.sin(ph - 1.4));
    final puffed = 1 + .14 * p.puff * (1 + .06 * math.sin(ph - .5));
    final dx = math.cos(p.toward), dy = math.sin(p.toward);

    final mp = MikkyPose()
      ..[MikkyProp.yaw] = p.yaw
      ..[MikkyProp.pitch] = p.pitch
      ..[MikkyProp.eyeScale] = p.eyeScale
      ..[MikkyProp.earLeft] = p.ears + .1 * math.sin(ph - 1.6)
      ..[MikkyProp.earRight] = p.ears + .1 * math.sin(ph - 1.9);
    final base = MikkyGeometry.posed(mp, r, time: t, eyeLeft: p.eyes, eyeRight: p.eyes);

    // One point of him, bent.
    Offset bend(double x, double y, {bool jelly = true}) {
      x *= puffed;
      y *= puffed;
      final len = math.sqrt(x * x + y * y);
      if (len > 1e-6) {
        final nx = x / len, ny = y / len;
        final s = nx * dx + ny * dy;
        final reach = math.min(1.2, len / r);
        final pull = (s > 0 ? stretch : squash) * s * s * reach * r;
        x += dx * pull;
        y += dy * pull;
        if (jelly) {
          final th = math.atan2(ny, nx);
          final ripple = r * p.wobble * reach * (.6 * math.sin(3 * th - ph) + .4 * math.sin(2 * th + ph + 1));
          x += nx * ripple;
          y += ny * ripple;
        }
      }
      // His ears, blown back: the higher, the more.
      final up = (-y / r - .55).clamp(0.0, 2.0);
      x -= dx * r * sweep * up;
      return Offset(x, y);
    }

    final contour = Float64List(base.contour.length);
    for (var i = 0; i < base.pointCount; i++) {
      final q = bend(base.contour[i * 2], base.contour[i * 2 + 1]);
      contour[i * 2] = q.dx;
      contour[i * 2 + 1] = q.dy;
    }
    final eyes = [
      for (final e in base.eyes)
        () {
          final q = bend(e.x, e.y, jelly: false);
          return EyeGeometry(
            x: q.dx - dx * r * p.eyeLift * .7,
            y: q.dy - r * p.eyeLift,
            rotation: e.rotation + lean * .3,
            scaleX: e.scaleX * puffed,
            scaleY: e.scaleY * puffed,
            width: e.width,
            height: e.height,
            fullHeight: e.fullHeight,
            shape: e.shape,
            side: e.side,
          );
        }(),
    ];
    final g = base.reshaped(contour: contour, eyes: eyes);

    // He stands a little away from where the air comes from.
    final center = Offset(
      size.width / 2 - dx * r * (.55 + .6 * p.stretch),
      size.height * .56 - dy.clamp(0.0, 1.0) * r * .2,
    );
    final pivot = center + Offset(0, r * .95);

    // His shadow on the ground stays put while he leans.
    canvas.drawOval(
      Rect.fromCenter(center: pivot + Offset(0, r * .06), width: r * 2.1 * puffed, height: r * .26),
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: theme.isLight ? .1 : .35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .06),
    );

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(lean);
    canvas.translate(-pivot.dx, -pivot.dy);
    final mouth = bend(dx * r * p.mouthAt + r * p.mouthX, dy * r * p.mouthAt, jelly: false);
    final along = p.mouthDepth * r * open, across = p.mouthSpan * r * open;

    // The air first, behind him: it rushes in and goes out of sight behind
    // his outline, as if he breathed it in.
    final lip = mouth + Offset(dx, dy) * (p.toward > 1 ? 0 : along * .35);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (p.file) _file(canvas, lip, Offset(dx, dy), r, breath, t);
    switch (p.air) {
      case GulpAir.lines:
        _lines(canvas, lip, r, t);
      case GulpAir.pixels:
        _pixels(canvas, lip, r, t);
      case GulpAir.whirl:
        _whirl(canvas, lip, r, t);
    }
    canvas.restore();

    MikkyPainter(
      geometry: g,
      center: center,
      rim: theme.mikkyRim,
      statusColor: theme.status,
      foreground: theme.foreground,
      showBadge: false,
    ).paint(canvas, size);

    canvas.translate(center.dx, center.dy);
    canvas.clipPath(
      Path()..addPolygon([for (var i = 0; i < g.pointCount; i++) Offset(contour[i * 2], contour[i * 2 + 1])], true),
    );
    _mouth(canvas, mouth, along, across, p.toward, r, p.mouthShape);
    canvas.restore();
  }

  /// The inside of his mouth, drawn with its depth going down [angle]
  /// (straight down for a front view): dark at the rim, lit in the middle,
  /// the throat at the back, a tongue at the bottom, a shine on the top lip.
  void _mouth(Canvas canvas, Offset at, double along, double across, double angle, double r, GulpMouth shape) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle - math.pi / 2);
    final w = across, h = along;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final outline = switch (shape) {
      GulpMouth.oval => Path()..addOval(rect),
      // The top lip nearly flat, a little dipped; the bottom a deep curve.
      GulpMouth.dee =>
        Path()
          ..moveTo(-w / 2, -h * .22)
          ..quadraticBezierTo(0, -h * .62, w / 2, -h * .22)
          ..cubicTo(w / 2, h * .42, w * .22, h / 2, 0, h / 2)
          ..cubicTo(-w * .22, h / 2, -w / 2, h * .42, -w / 2, -h * .22)
          ..close(),
      GulpMouth.soft =>
        Path()..addRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: Radius.elliptical(w * .3, h * .45),
            topRight: Radius.elliptical(w * .3, h * .45),
            bottomLeft: Radius.elliptical(w * .4, h * .55),
            bottomRight: Radius.elliptical(w * .4, h * .55),
          ),
        ),
    };
    canvas.drawPath(
      outline,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, .15),
          radius: .8,
          colors: [Color(0xFFFF6676), Color(0xFFE5243F), Color(0xFF9C0B24), Color(0xFF52040F)],
          stops: [0, .4, .8, 1],
        ).createShader(rect),
    );
    canvas.clipPath(outline);
    // The throat, at the back: up and in the middle, seen from the front.
    final throat = Rect.fromCenter(center: Offset(0, -h * .1), width: w * .85, height: h * .6);
    canvas.drawOval(
      throat,
      Paint()..shader = const RadialGradient(colors: [Color(0x662A020A), Color(0x002A020A)]).createShader(throat),
    );
    // The tongue, at the bottom.
    final tongue = Rect.fromCenter(center: Offset(0, h * .4), width: w * .72, height: h * .48);
    canvas.drawOval(
      tongue,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.4),
          colors: [Color(0xFFFF9AA8), Color(0xFFE5506A)],
        ).createShader(tongue),
    );
    // The top lip's shadow, then a soft shine, like a lit sweet.
    final top = Rect.fromLTWH(-w / 2, -h / 2, w, h * .38);
    canvas.drawRect(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99300208), Color(0x00300208)],
        ).createShader(top),
    );
    final shine = Rect.fromCenter(center: Offset(-w * .22, -h * .08), width: w * .22, height: h * .13);
    canvas.drawOval(
      shine,
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .03),
    );
    canvas.restore();
  }

  /// The angles the air comes from, and where each stroke is in its trip
  /// (0: far away, 1: in his mouth).
  Iterable<(double, double, int)> _streams(int n, double t, double speed) sync* {
    for (var i = 0; i < n; i++) {
      final u = n == 1 ? 0.0 : i / (n - 1) * 2 - 1;
      final a = pose.toward + pose.spread * u + .08 * math.sin(i * 2.7);
      final f = (t / pose.period * speed + i * .618) % 1;
      yield (a, f, i);
    }
  }

  Color get _ink => theme.isLight ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

  /// Thin strokes, longer far away, thinner at their tail.
  void _lines(Canvas canvas, Offset lip, double r, double t) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final (a, f, i) in _streams(pose.spread > 2 ? 14 : 9, t, 1.4)) {
      final eased = f * f * (3 - 2 * f);
      final head = r * (2.8 - 2.15 * eased);
      final length = r * (.75 - .4 * eased);
      final alpha = math.sin(f * math.pi) * .8;
      if (alpha < .02) continue;
      final bendAmount = r * .1 * math.sin(i * 1.7);
      final dir = Offset(math.cos(a), math.sin(a));
      final side = Offset(-dir.dy, dir.dx);
      const steps = 6;
      for (var k = 0; k < steps; k++) {
        final d0 = head + length * k / steps, d1 = head + length * (k + 1) / steps;
        final p0 = lip + dir * d0 + side * bendAmount * (d0 / (r * 2.8)) * (d0 / (r * 2.8));
        final p1 = lip + dir * d1 + side * bendAmount * (d1 / (r * 2.8)) * (d1 / (r * 2.8));
        paint
          ..color = _ink.withValues(alpha: alpha * (1 - k / steps))
          ..strokeWidth = math.max(.6, r * .04 * (1 - k / steps));
        canvas.drawLine(p0, p1, paint);
      }
    }
  }

  /// Streaks of pixels in our blue, bright at the head.
  void _pixels(Canvas canvas, Offset lip, double r, double t) {
    final px = (r * .07).roundToDouble().clamp(2.0, 4.0);
    final paint = Paint()..isAntiAlias = false;
    final levels = PixelFxPalette.signatureBlue.levels;
    for (final (a, f, _) in _streams(11, t, 1.6)) {
      final eased = f * f;
      final head = r * (2.7 - 2.1 * eased);
      final alpha = math.sin(f * math.pi);
      if (alpha < .05) continue;
      final dir = Offset(math.cos(a), math.sin(a));
      for (var k = 0; k < 4; k++) {
        final q = lip + dir * (head + k * px * 1.3);
        paint.color = levels[math.min(k, levels.length - 1)].withValues(alpha: alpha * (1 - k * .2));
        canvas.drawRect(
          Rect.fromLTWH((q.dx / px).roundToDouble() * px, (q.dy / px).roundToDouble() * px, px, px),
          paint,
        );
      }
    }
  }

  /// Dashes turning into his mouth, the circle getting smaller.
  void _whirl(Canvas canvas, Offset lip, double r, double t) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const n = 10;
    for (var i = 0; i < n; i++) {
      final f = (t / pose.period * 1.2 + i / n) % 1;
      final radius = r * (1.9 * (1 - f) + .2);
      final start = pose.toward - math.pi / 2 + i * 2.4 + f * 4;
      final alpha = math.sin(f * math.pi) * .75;
      if (alpha < .02) continue;
      // The whirl seen a little from the side: flatter across his mouth.
      canvas.save();
      canvas.translate(lip.dx + math.cos(pose.toward) * radius * .55, lip.dy + math.sin(pose.toward) * radius * .55);
      canvas.rotate(pose.toward);
      canvas.scale(.55, 1);
      paint
        ..color = _ink.withValues(alpha: alpha)
        ..strokeWidth = math.max(.8, r * .045 * (1 - f * .5)) / .55;
      canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: radius), start, .7 + .4 * f, false, paint);
      canvas.restore();
    }
  }

  /// A file held in the wind in front of him, stretched toward his mouth.
  void _file(Canvas canvas, Offset lip, Offset dir, double r, double breath, double t) {
    final at = lip + dir * r * (1.95 - .18 * breath);
    final w = r * .62, h = r * .78;
    final toMouth = math.atan2(-dir.dy, -dir.dx);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(toMouth);
    canvas.scale(1.18 + .06 * breath, .88);
    canvas.rotate(-toMouth + .18 * math.sin(t * 2 * math.pi / pose.period * 2));
    final page = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Radius.circular(w * .12),
    );
    canvas.drawRRect(page.shift(Offset(0, r * .04)), Paint()..color = const Color(0x22000000));
    canvas.drawRRect(page, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRRect(
      page,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, r * .02)
        ..color = const Color(0xFFD1D1D6),
    );
    final line = Paint()
      ..color = const Color(0xFFC7C7CC)
      ..strokeWidth = math.max(1, h * .05)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = -h * .05 + i * h * .16;
      canvas.drawLine(Offset(-w * .3, y), Offset(w * (i == 2 ? .05 : .3), y), line);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w * .3, -h * .34, w * .36, h * .13), Radius.circular(h * .04)),
      Paint()..color = PixelFxPalette.signatureBlue.levels[1],
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GulpPainter old) =>
      old.pose != pose || old.theme != theme || old.radius != radius || old.time != time;
}
