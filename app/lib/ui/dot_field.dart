import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// How the dots of a [DotField] spread: « glitched » (user, 2026-10-05,
/// chosen over even dots and two dense spots), in two trials.
enum DotFieldStyle {
  /// Squares of 4 × 4 dots, a third very present, the others faint.
  glitch,

  /// Big squares (6 × 6) more or less present, sprinkled with small bright
  /// ones (2 × 2).
  glitchMixed,
}

/// Small grey dots behind the notch's apps (trial, 2026-10-05: « des
/// points gris assez petits pour avoir cet effet de loin »): always there
/// on the right ([solidFrom] and beyond), they drop out towards [goneAt],
/// in the left part, where none are left — a soft line between the parts.
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
            // Grey, a little darker since the first trial (« pas assez
            // noir »): a texture, not a pattern to read.
            color: ui.isLight ? const Color(0xFF6E6E73).withValues(alpha: .7) : const Color(0xFFFFFFFF).withValues(alpha: .34),
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

  /// Between two dots; a dot's side (« trop de points, un peu trop
  /// petits » at 6 and 1.2).
  static const _step = 8.0, _dot = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final paint = Paint()..isAntiAlias = false;
    final cols = (size.width / _step).ceil(), rows = (size.height / _step).ceil();
    // One strength per square, at random; never nothing on the right.
    final big = <(int, int), double>{}, small = <(int, int), bool>{};
    double square(int c, int r, int side) =>
        big.putIfAbsent((c ~/ side, r ~/ side), () => rng.nextDouble() < .33 ? .85 + .15 * rng.nextDouble() : .14 + .26 * rng.nextDouble());
    bool sparkle(int c, int r) => small.putIfAbsent((c ~/ 2, r ~/ 2), () => rng.nextDouble() < .1);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = c * _step + _step / 2, y = r * _step + _step / 2;
        final fade = _smooth(((x - goneAt) / (solidFrom - goneAt)).clamp(0.0, 1.0));
        if (fade <= 0) continue;
        final strength = switch (style) {
          DotFieldStyle.glitch => square(c, r, 4),
          DotFieldStyle.glitchMixed => sparkle(c, r) ? 1.0 : square(c, r, 6) * .8,
        };
        // In the fade, dots drop out at random instead of only paling.
        if (fade < 1 && rng.nextDouble() > fade) continue;
        final a = strength * (.5 + .5 * fade);
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
