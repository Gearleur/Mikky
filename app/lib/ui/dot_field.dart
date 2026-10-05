import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Small grey dots behind the notch's apps (2026-10-05, chosen on the
/// boards): « glitched », big squares of 6 × 6 dots more or less present,
/// sprinkled with small bright ones (2 × 2); 1.2 px dots every 8 px, a
/// texture from afar. Whole under the apps ([solidFrom] and beyond), they
/// drop out at random towards [goneAt], in Mikky's part, where none are
/// left — a soft line between the two parts; they fade at the top and the
/// bottom too, and only a little on the right.
class DotField extends StatelessWidget {
  const DotField({super.key, required this.solidFrom, required this.goneAt, this.seed = 5});

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
            solidFrom: solidFrom,
            goneAt: goneAt,
            seed: seed,
            // Grey, a little dark (« pas assez noir » paler): a texture, not
            // a pattern to read.
            color: ui.isLight ? const Color(0xFF6E6E73).withValues(alpha: .7) : const Color(0xFFFFFFFF).withValues(alpha: .34),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.solidFrom, required this.goneAt, required this.seed, required this.color});

  final double solidFrom, goneAt;
  final int seed;
  final Color color;

  /// Between two dots (6 made « trop de points »); a dot's side (1.4 and
  /// 1.6 were « trop gros »).
  static const _step = 8.0, _dot = 1.2;

  /// The fade at the top and the bottom; on the right, its length and how
  /// pale it gets there (« un fondu plus léger sur la droite »).
  static const _edge = 44.0, _right = 90.0, _rightPale = .5;

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
        final left = _smooth(((x - goneAt) / (solidFrom - goneAt)).clamp(0.0, 1.0));
        final vertical = _smooth((y / _edge).clamp(0.0, 1.0)) * _smooth(((size.height - y) / _edge).clamp(0.0, 1.0));
        final right = 1 - (1 - _rightPale) * _smooth(((x - (size.width - _right)) / _right).clamp(0.0, 1.0));
        final fade = left * vertical * right;
        if (fade <= 0) continue;
        final strength = sparkle(c, r) ? 1.0 : square(c, r) * .8;
        // In the fade, dots drop out at random instead of only paling.
        if (fade < 1 && rng.nextDouble() > fade) continue;
        paint.color = color.withValues(alpha: color.a * strength * (.5 + .5 * fade));
        canvas.drawRect(Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), _dot, _dot), paint);
      }
    }
  }

  static double _smooth(double t) => t * t * (3 - 2 * t);

  @override
  bool shouldRepaint(_DotsPainter old) => old.solidFrom != solidFrom || old.goneAt != goneAt || old.seed != seed || old.color != color;
}
