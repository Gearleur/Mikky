import 'dart:math' as math;

/// Maps a progress in [0, 1] to an eased progress (0 → 0, 1 → 1).
typedef Easing = double Function(double t);

/// The easings of the prototypes and of Mochi (`BotEngine.swift`).
abstract final class Easings {
  static double linear(double t) => t;

  /// Cubic ease-out.
  static double out(double t) => 1 - math.pow(1 - t, 3).toDouble();

  /// Cubic ease-in-out.
  static double inOut(double t) =>
      t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  /// Ease-out with a small overshoot.
  static double back(double t) {
    const c1 = 1.7, c3 = c1 + 1;
    return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
  }
}
