import 'dart:math' as math;

/// Frame-rate independent exponential smoothing of [current] toward [target].
///
/// After one second, only [remainingPerSecond] of the initial gap is left,
/// whatever the number of frames in that second.
double approach(double current, double target, double remainingPerSecond, double dt) =>
    current + (target - current) * (1 - math.pow(remainingPerSecond, dt));
