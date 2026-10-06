import 'dart:math' as math;

import 'spring.dart';

/// Maps a progress in [0, 1] to an eased progress (0 → 0, 1 → 1).
typedef Easing = double Function(double t);

/// The easings of the prototypes and of Mochi (`BotEngine.swift`).
abstract final class Easings {
  static double linear(double t) => t;

  /// Cubic ease-out.
  static double out(double t) => 1 - math.pow(1 - t, 3).toDouble();

  /// Cubic ease-in: a fall, a start.
  static double inCubic(double t) => t * t * t;

  /// A quick start and a long, soft end.
  static double outQuint(double t) => 1 - math.pow(1 - t, 5).toDouble();

  /// Cubic ease-in-out.
  static double inOut(double t) =>
      t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  /// Ease-out with a small overshoot.
  static double back(double t) {
    const c1 = 1.7, c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
  }

  /// The way a [spec] spring goes from 0 to 1, played over [seconds] (its
  /// overshoots and its settling, exactly), ending on 1.
  static Easing spring(SpringSpec spec, double seconds) {
    final w = math.sqrt(spec.stiffness), z = spec.dampingRatio;
    double x(double t) {
      if (z < 1) {
        final wd = w * math.sqrt(1 - z * z);
        return 1 - math.exp(-z * w * t) * (math.cos(wd * t) + z * w / wd * math.sin(wd * t));
      }
      if (z == 1) return 1 - math.exp(-w * t) * (1 + w * t);
      final s = w * math.sqrt(z * z - 1);
      final r1 = -z * w + s, r2 = -z * w - s;
      return 1 - (r2 * math.exp(r1 * t) - r1 * math.exp(r2 * t)) / (r2 - r1);
    }

    // What the spring has not settled yet at the end is spread over the
    // way, so it ends exactly on 1.
    final rest = 1 - x(seconds);
    return (q) => x(q * seconds) + rest * q;
  }
}
