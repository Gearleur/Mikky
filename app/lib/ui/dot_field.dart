import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// How the dots of a [DotField] spread.
enum DotFieldStyle {
  /// Even: the same everywhere, then the fade.
  even,

  /// Two places where they are dense, spreading out from them.
  hotspots,

  /// « Glitched »: small squares of dots, from very present to faint, at
  /// random; in the fade, they drop out at random.
  glitch,
}

/// Tiny grey dots behind the notch's apps (trial, 2026-10-05: « des points
/// gris assez petits pour avoir cet effet de loin »): always there on the
/// right ([solidFrom] and beyond), they fade smoothly to nothing at
/// [goneAt], in the left part — a soft line between the two parts.
class DotField extends StatelessWidget {
  const DotField({super.key, required this.style, required this.solidFrom, required this.goneAt, this.seed = 5});

  final DotFieldStyle style;

  /// From this x on, the dots are whole; at [goneAt] (left of it), gone.
  final double solidFrom, goneAt;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _DotsPainter(
            style: style,
            solidFrom: solidFrom,
            goneAt: goneAt,
            seed: seed,
            // Grey, quiet: a texture, not a pattern to read.
            color: ui.isLight ? const Color(0xFF8E8E93).withValues(alpha: .55) : const Color(0xFFFFFFFF).withValues(alpha: .26),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.style, required this.solidFrom, required this.goneAt, required this.seed, required this.color});

  final DotFieldStyle style;
  final double solidFrom, goneAt;
  final int seed;
  final Color color;

  /// Between two dots; a dot's side.
  static const _step = 6.0, _dot = 1.2;

  /// The glitch's squares: this many dots a side.
  static const _block = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final paint = Paint()..isAntiAlias = false;
    final cols = (size.width / _step).ceil(), rows = (size.height / _step).ceil();
    // The glitch: one strength per square, at random (always a little).
    final blocks = <(int, int), double>{};
    // A third of the squares very present, the others faint.
    double blockOf(int c, int r) => blocks.putIfAbsent((c ~/ _block, r ~/ _block), () => rng.nextDouble() < .33 ? .85 + .15 * rng.nextDouble() : .12 + .25 * rng.nextDouble());
    // Two places where they are dense, on the right part.
    final hot = [Offset(size.width - 70, size.height * .22), Offset(solidFrom + 90, size.height * .82)];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = c * _step + _step / 2, y = r * _step + _step / 2;
        final fade = _smooth(((x - goneAt) / (solidFrom - goneAt)).clamp(0.0, 1.0));
        if (fade <= 0) continue;
        final strength = switch (style) {
          DotFieldStyle.even => 1.0,
          DotFieldStyle.hotspots => math.max(.16, hot.map((h) => math.exp(-((Offset(x, y) - h).distanceSquared) / (2 * 80 * 80))).reduce(math.max)),
          DotFieldStyle.glitch => blockOf(c, r),
        };
        var a = strength * fade;
        // In the fade, the glitch's dots drop out instead of only paling.
        if (style == DotFieldStyle.glitch && fade < 1 && rng.nextDouble() > fade) continue;
        if (style == DotFieldStyle.glitch) a = strength * (.5 + .5 * fade);
        if (a < .02) continue;
        paint.color = color.withValues(alpha: color.a * a);
        canvas.drawRect(Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), _dot, _dot), paint);
      }
    }
  }

  static double _smooth(double t) => t * t * (3 - 2 * t);

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.style != style || old.solidFrom != solidFrom || old.goneAt != goneAt || old.seed != seed || old.color != color;
}
