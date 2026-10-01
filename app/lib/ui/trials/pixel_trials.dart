import 'dart:math' as math;

import '../pixel_fx.dart';

// Trials, shown on the design boards only: pixel effects set aside for
// the calm firework (design.md §12, point 4: to sort once chosen).

/// A cross star that grows from a dot, throws rays and diagonal dots,
/// then goes out; two small ones twinkle in the corners.
class Sparkle extends PixelEffect {
  const Sparkle();

  @override
  int get grid => 9;

  @override
  double get still => .72;

  @override
  double at(double t, int dx, int dy) {
    // The big star: born, grows, goes out, rests (1.8 s).
    final main = _star(dx, dy, (t / 1.8) % 1, 4);
    // Two small ones in the corners, out of step.
    final a = _star(dx + 3, dy + 3, (t / 1.3 + .4) % 1, 1);
    final b = _star(dx - 3, dy - 3, (t / 1.5 + .75) % 1, 1);
    return math.max(main, math.max(a, b));
  }

  /// A cross star at the origin, [reach] pixels at most, at phase [p].
  static double _star(int dx, int dy, double p, int reach) {
    if (p > .8) return 0;
    final s = math.sin(p / .8 * math.pi);
    final ax = dx.abs(), ay = dy.abs();
    if (ax == 0 && ay == 0) return .35 + .65 * s;
    final len = reach * s;
    // The rays: bright near the heart, darker at the tip.
    if ((ax == 0 || ay == 0) && ax + ay <= len + .5) return s * (1 - (ax + ay) / (len + 1.2)) + .15;
    // Dots on the diagonals, a step away, once the star is big.
    if (reach > 1 && ax == ay && ax == (len > 2.6 ? 2 : 1) && s > .5) return .3 + .2 * s;
    return 0;
  }
}

/// A burst in the middle, in eight directions, that opens as it lights
/// up and closes again, over and over; the tips cool as it opens.
class Firework extends PixelEffect {
  const Firework();

  @override
  int get grid => 9;

  @override
  double get still => 1.2;

  @override
  double at(double t, int dx, int dy) {
    // No launch: it stays in the middle, opens as it lights up, then
    // closes again, over and over (user request, 2026-09-30).
    final e = (1 - math.cos((t / 2.4) * math.pi * 2)) / 2;
    final r = .7 + e * 3.3;
    if (dx == 0 && dy == 0) return 1 - .15 * e;
    final d = math.sqrt((dx * dx + dy * dy).toDouble());
    // Along the eight directions, and the ones in between once it is open.
    final angle = math.atan2(dy.toDouble(), dx.toDouble());
    final onDir = (angle / (math.pi / 4) - (angle / (math.pi / 4)).roundToDouble()).abs() < .12;
    final between = (angle / (math.pi / 8) - (angle / (math.pi / 8)).roundToDouble()).abs() < .1 && e > .45;
    if (!onDir && !between) return 0;
    // The head of each spark, and a short trail behind it.
    final head = 1 - ((d - r).abs() / 1.1);
    final trail = d < r ? (1 - (r - d) / 3.2) * .7 : 0;
    // Open, it cools a little: white small, deeper colors at its widest.
    final cool = 1 - e * .35;
    return math.max(0, math.max(head, trail)) * cool * (between ? .75 : 1);
  }
}

/// Spiral arms around a white core, turning slowly, scattered pixels on
/// the edge.
class Galaxy extends PixelEffect {
  const Galaxy();

  @override
  int get grid => 9;

  @override
  double get still => 1;

  @override
  double at(double t, int dx, int dy) {
    final x = dx + grid ~/ 2, y = dy + grid ~/ 2;
    final r = math.sqrt((dx * dx + dy * dy).toDouble());
    if (r < .5) return 1;
    final theta = math.atan2(dy.toDouble(), dx.toDouble());
    // Two arms winding out, turning once in 9 s.
    if (r > 4.6) return 0;
    final wave = .5 + .5 * math.cos(2 * theta - 1.7 * r + t * (math.pi * 2 / 9));
    // Thin arms: only the crest of the wave.
    final arm = math.pow(wave, 5).toDouble();
    final fade = math.exp(-r / 2.8);
    // A little grain, the same for a pixel, so the edges scatter.
    final grain = .7 + .6 * pixelHash(x * 17 + y * 31);
    final twinkle = r > 2.5 && pixelHash(x * 7 + y * 13 + (t * 3).floor()) > .95 ? .4 : 0.0;
    final core = r < 1.1 ? .75 : 0.0;
    return math.max(math.max(arm * (.3 + fade * 1.3) * grain, core), twinkle);
  }
}
