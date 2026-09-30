import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion.dart';
import '../pixel_fx.dart';

// A trial, shown on the design boards only (set aside, design.md §12,
// point 4).

/// A small star that thinks: a bright core in a pale glow, thin orange
/// and pink rays of uneven lengths that tremble, the whole swaying a
/// little (user request, 2026-09-30, after a sparkler star; tried on
/// Mikky, then set aside here, like the launcher).
class ThinkingStar extends StatelessWidget {
  const ThinkingStar({super.key, this.size = 22});

  final double size;

  /// Long enough that the loop's seam never shows.
  static const _period = 30.0;

  @override
  Widget build(BuildContext context) => Looping(
    period: const Duration(seconds: 30),
    frozenAt: .02,
    builder: (context, t) => CustomPaint(size: Size.square(size), painter: _StarPainter(t * _period)),
  );
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.t);

  /// Seconds.
  final double t;

  static const core = Color(0xFFFFFFFF);
  static const glow = Color(0xFFBFE3FF);
  static const warm = Color(0xFFFF9A4D);
  static const pink = Color(0xFFFF5C8A);

  @override
  void paint(Canvas canvas, Size size) {
    final big = size.shortestSide / 2 * (1 + .05 * math.sin(t * 4.1));
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    // It stirs: a slow sway and a quicker shiver.
    canvas.rotate(.12 * math.sin(t * 1.7) + .04 * math.sin(t * 6.3));
    canvas.drawCircle(
      Offset.zero,
      big * .62,
      Paint()
        ..shader = RadialGradient(colors: [
          glow.withValues(alpha: .75),
          glow.withValues(alpha: .22),
          glow.withValues(alpha: 0),
        ], stops: const [0, .45, 1])
            .createShader(Rect.fromCircle(center: Offset.zero, radius: big * .62)),
    );
    const rays = 16;
    for (var i = 0; i < rays; i++) {
      // Fixed unevenness per ray, and each one trembles on its own.
      final h = pixelHash(i);
      final angle = i / rays * math.pi * 2 + (h - .5) * .22;
      final long = (i.isEven ? .78 : .48) + h * .28;
      final length = big * long * (1 + .14 * math.sin(t * (6 + h * 5) + h * 20));
      final base = big * (.025 + .018 * h);
      final dir = Offset(math.cos(angle), math.sin(angle));
      final side = Offset(-dir.dy, dir.dx) * base;
      final from = dir * (big * .08);
      final tip = dir * length;
      canvas.drawPath(
        Path()
          ..moveTo(from.dx + side.dx, from.dy + side.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(from.dx - side.dx, from.dy - side.dy)
          ..close(),
        Paint()
          ..shader = LinearGradient(colors: [
            core,
            warm.withValues(alpha: .95),
            (h > .5 ? pink : warm).withValues(alpha: 0),
          ], stops: const [0, .35, 1])
              .createShader(Rect.fromPoints(from, tip)),
      );
    }
    // The core: a small bright point with its own soft halo.
    canvas.drawCircle(
      Offset.zero,
      big * .2,
      Paint()
        ..shader = RadialGradient(colors: [core, core.withValues(alpha: .85), core.withValues(alpha: 0)], stops: const [0, .3, 1])
            .createShader(Rect.fromCircle(center: Offset.zero, radius: big * .2)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.t != t;
}
