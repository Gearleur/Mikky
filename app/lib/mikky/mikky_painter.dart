import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:mikky_engine/mikky_engine.dart';

const _ink = Color(0xFF0C0C0E);
const _eyeWhite = Color(0xFFF7F7F7);
const _heartPink = Color(0xFFFF4D6D);
const _starGold = Color(0xFFFFD25A);
const _sweatBlue = Color(0xFF7CC4FF);

/// Draws one frame of Mikky's geometry, centered on [center].
class MikkyPainter extends CustomPainter {
  MikkyPainter({
    required this.geometry,
    required this.center,
    required this.statusColor,
    required this.foreground,
    this.rim,
    this.showBadge = true,
  });

  final MikkyGeometry geometry;
  final Offset center;

  /// Outline color, to separate Mikky from a dark background.
  final Color? rim;

  /// Theme color of an agent status (badges).
  final Color Function(AgentStatus) statusColor;

  /// Text color of the background Mikky is on (the "z" of sleep).
  final Color foreground;
  final bool showBadge;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final r = g.radius;
    final points = [
      for (var i = 0; i < g.pointCount; i++) Offset(g.contour[i * 2], g.contour[i * 2 + 1]),
    ];
    final body = Path()..addPolygon(points, true);

    canvas.save();
    canvas.translate(center.dx + g.translateX, center.dy + g.translateY);
    canvas.rotate(g.tilt);
    canvas.scale(g.scaleX, g.scaleY);

    // The body and the fur balls that came out of it: all of them are him.
    final parts = [
      body,
      for (final s in g.satellites)
        Path()..addPolygon([for (var i = 0; i < s.length ~/ 2; i++) Offset(s[i * 2], s[i * 2 + 1])], true),
    ];
    final rim = this.rim;
    for (final part in parts) {
      canvas.drawPath(part, Paint()..color = _ink);
      if (rim != null) {
        canvas.drawPath(
          part,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, r * .045)
            ..color = rim,
        );
      }
    }

    canvas.save();
    canvas.clipPath(body);
    for (final eye in g.eyes) {
      canvas.save();
      canvas.translate(eye.x, eye.y);
      canvas.rotate(eye.rotation);
      canvas.scale(eye.scaleX, eye.scaleY);
      _eye(canvas, eye, r, g.time);
      canvas.restore();
    }
    canvas.restore();
    canvas.restore();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    for (final p in g.particles) {
      _particle(canvas, p);
    }
    // Too small to read in the closed island.
    if (showBadge && r >= 16) _badge(canvas, g);
    canvas.restore();
  }

  void _eye(Canvas canvas, EyeGeometry e, double r, double time) {
    final w = e.width, h = e.height, full = e.fullHeight;
    final fill = Paint()..color = _eyeWhite;
    Paint line(double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = _eyeWhite;
    switch (e.shape) {
      case EyeShape.oval:
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: w, height: h), fill);
      case EyeShape.happy:
        // "^": content arcs.
        canvas.drawArc(
          Rect.fromCircle(center: Offset(0, full * .2), radius: w * .7),
          math.pi * 1.12,
          math.pi * .76,
          false,
          line(r * .15),
        );
      case EyeShape.closed:
        // "‿": asleep.
        canvas.drawArc(
          Rect.fromCircle(center: Offset(0, -full * .05), radius: w * .7),
          math.pi * .12,
          math.pi * .76,
          false,
          line(r * .12),
        );
      case EyeShape.flat:
        final t = math.max(w * .34, 1.2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, full * .1), width: w * 1.25, height: t), Radius.circular(t / 2)),
          fill,
        );
      case EyeShape.tired:
        // Heavy eyelids: only the lower half of the oval shows.
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(-w, -h / 2 + h * .45, w, h));
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: w, height: h), fill);
        canvas.restore();
      case EyeShape.slit:
        canvas.save();
        canvas.rotate(e.side * .28);
        canvas.drawOval(Rect.fromCenter(center: Offset(0, full * .08), width: w * 1.2, height: math.max(w * .26, 1.2)), fill);
        canvas.restore();
      case EyeShape.spiral:
        canvas.save();
        canvas.rotate(time * 6 * e.side);
        final path = Path();
        const turns = 2.4;
        for (var i = 0; i <= 72; i++) {
          final a = i / 72 * turns * math.pi * 2;
          final rr = w * .08 + (w * 1.05) * (i / 72);
          final pt = Offset(math.cos(a) * rr, math.sin(a) * rr);
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path, line(math.max(1, r * .075)));
        canvas.restore();
      case EyeShape.heart:
        canvas.drawPath(_heart(w * 1.7), Paint()..color = _heartPink);
      case EyeShape.star:
        canvas.drawPath(_star(w * .95, w * .42), Paint()..color = _starGold);
    }
  }

  void _particle(Canvas canvas, MikkyParticle p) {
    if (p.alpha <= 0) return;
    canvas.save();
    canvas.translate(p.x, p.y);
    canvas.rotate(p.rotation);
    Color a(Color c) => c.withValues(alpha: c.a * p.alpha);
    switch (p.kind) {
      case ParticleKind.sparkle:
        canvas.drawPath(_star(p.size, p.size * .28, points: 4), Paint()..color = a(_starGold));
      case ParticleKind.star:
        canvas.drawPath(_star(p.size, p.size * .45), Paint()..color = a(_starGold));
      case ParticleKind.heart:
        canvas.drawPath(_heart(p.size * 2), Paint()..color = a(_heartPink));
      case ParticleKind.sweat:
        final s = p.size;
        final drop = Path()
          ..moveTo(0, -s)
          ..quadraticBezierTo(s * .75, 0, 0, s * .7)
          ..quadraticBezierTo(-s * .75, 0, 0, -s)
          ..close();
        canvas.drawPath(drop, Paint()..color = a(_sweatBlue));
      case ParticleKind.sleep:
        final s = p.size;
        final z = Path()
          ..moveTo(-s * .5, -s * .5)
          ..lineTo(s * .5, -s * .5)
          ..lineTo(-s * .5, s * .5)
          ..lineTo(s * .5, s * .5);
        canvas.drawPath(
          z,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, s * .22)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = a(foreground),
        );
    }
    canvas.restore();
  }

  void _badge(Canvas canvas, MikkyGeometry g) {
    final b = g.badge;
    if (b == null) return;
    final r = g.radius;
    final color = statusColor(b.color);
    final c = Offset(g.badgeX, g.badgeY);
    final h = r * .5;
    switch (b.kind) {
      case BadgeKind.dot:
        canvas.drawCircle(c, h * .32, Paint()..color = color);
      case BadgeKind.dots:
        final w = h * 1.9;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: w, height: h), Radius.circular(h / 2)),
            Paint()..color = color);
        for (var i = 0; i < 3; i++) {
          // A wave through the three dots.
          final lift = math.max(0.0, math.sin(g.time * 6 - i * .9)) * h * .12;
          canvas.drawCircle(c + Offset((i - 1) * h * .5, -lift), h * .12, Paint()..color = _eyeWhite);
        }
      case BadgeKind.bang || BadgeKind.question:
        canvas.drawCircle(c, h * .6, Paint()..color = color);
        final text = TextPainter(
          text: TextSpan(
            text: b.kind == BadgeKind.bang ? '!' : '?',
            style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: h * .85, color: _eyeWhite, height: 1),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, c - Offset(text.width / 2, text.height / 2));
        text.dispose();
    }
  }

  static Path _heart(double size) {
    final s = size / 2;
    return Path()
      ..moveTo(0, s * .75)
      ..cubicTo(-s * 1.1, s * .05, -s * .75, -s * .9, 0, -s * .35)
      ..cubicTo(s * .75, -s * .9, s * 1.1, s * .05, 0, s * .75)
      ..close();
  }

  static Path _star(double outer, double inner, {int points = 5}) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final rr = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / points;
      final pt = Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  // A new painter is built for each frame, with a new geometry.
  @override
  bool shouldRepaint(MikkyPainter oldDelegate) => true;
}
