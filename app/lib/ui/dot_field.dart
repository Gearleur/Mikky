import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Small grey dots behind the notch's apps (trial, 2026-10-05), «
/// glitched » (chosen over even dots, two dense spots and squares of one
/// size): big squares of 6 × 6 dots more or less present, sprinkled with
/// small bright ones (2 × 2). Always there on the right ([solidFrom] and
/// beyond), they drop out at random towards [goneAt], in the left part,
/// where none are left — a soft line between the two parts.
class DotField extends StatelessWidget {
  const DotField({super.key, required this.solidFrom, required this.goneAt, this.dot = 1.2, this.seed = 5});

  /// From this x on, the dots are whole; at [goneAt] (left of it), gone.
  final double solidFrom, goneAt;

  /// A dot's side (trials: 1.2, 1.4; 1.6 was « trop gros »).
  final double dot;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _DotsPainter(
            solidFrom: solidFrom,
            goneAt: goneAt,
            dot: dot,
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
  _DotsPainter({required this.solidFrom, required this.goneAt, required this.dot, required this.seed, required this.color});

  final double solidFrom, goneAt, dot;
  final int seed;
  final Color color;

  /// Between two dots (6 made « trop de points »).
  static const _step = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final paint = Paint()..isAntiAlias = false;
    final cols = (size.width / _step).ceil(), rows = (size.height / _step).ceil();
    // One strength per big square, at random, never nothing; a few small
    // squares bright.
    final big = <(int, int), double>{}, small = <(int, int), bool>{};
    double square(int c, int r) =>
        big.putIfAbsent((c ~/ 6, r ~/ 6), () => rng.nextDouble() < .33 ? .85 + .15 * rng.nextDouble() : .14 + .26 * rng.nextDouble());
    bool sparkle(int c, int r) => small.putIfAbsent((c ~/ 2, r ~/ 2), () => rng.nextDouble() < .1);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = c * _step + _step / 2, y = r * _step + _step / 2;
        final fade = _smooth(((x - goneAt) / (solidFrom - goneAt)).clamp(0.0, 1.0));
        if (fade <= 0) continue;
        final strength = sparkle(c, r) ? 1.0 : square(c, r) * .8;
        // In the fade, dots drop out at random instead of only paling.
        if (fade < 1 && rng.nextDouble() > fade) continue;
        paint.color = color.withValues(alpha: color.a * strength * (.5 + .5 * fade));
        canvas.drawRect(Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), dot, dot), paint);
      }
    }
  }

  static double _smooth(double t) => t * t * (3 - 2 * t);

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.solidFrom != solidFrom || old.goneAt != goneAt || old.dot != dot || old.seed != seed || old.color != color;
}
