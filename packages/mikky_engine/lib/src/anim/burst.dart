import 'dart:math' as math;

/// One spark of a [Burst], drawn once at random (a fixed seed: the same
/// burst every time).
class Spark {
  const Spark(this.angle, this.speed, this.size, this.life, this.delay, this.alpha);

  /// Radians (0: right, y down); pixels per second; pixels; seconds;
  /// seconds after the burst; 0 to 1.
  final double angle, speed, size, life, delay, alpha;
}

/// Where a spark is at one instant, from the burst's origin.
class SparkAt {
  const SparkAt(this.x, this.y, this.vx, this.vy, this.size, this.alpha, this.progress);

  /// Pixels; pixels per second (for streaks drawn along the way).
  final double x, y, vx, vy;
  final double size;

  /// Its brightness now (fades in quickly, out slowly), times its own.
  final double alpha;

  /// 0 born, 1 gone.
  final double progress;
}

/// Particles thrown out at once, as a function of time: nothing to update,
/// any instant can be drawn (the time bar of the boards, a still image).
class Burst {
  Burst({
    required int seed,
    required int count,
    double angleFrom = 0,
    double angleTo = math.pi * 2,
    required double speedMin,
    required double speedMax,
    required double sizeMin,
    required double sizeMax,
    required double lifeMin,
    required double lifeMax,
    double delayMax = 0,
    double alphaMin = .5,
    double alphaMax = 1,
    this.drag = 0,
    this.gravity = 0,
  }) : sparks = _draw(
         seed,
         count,
         angleFrom,
         angleTo,
         speedMin,
         speedMax,
         sizeMin,
         sizeMax,
         lifeMin,
         lifeMax,
         delayMax,
         alphaMin,
         alphaMax,
       );

  final List<Spark> sparks;

  /// How fast they slow down (per second), and fall (pixels per second²).
  final double drag, gravity;

  static List<Spark> _draw(
    int seed,
    int count,
    double a0,
    double a1,
    double v0,
    double v1,
    double s0,
    double s1,
    double l0,
    double l1,
    double delay,
    double al0,
    double al1,
  ) {
    final rng = math.Random(seed);
    double between(double a, double b) => a + (b - a) * rng.nextDouble();
    return [
      for (var i = 0; i < count; i++)
        Spark(between(a0, a1), between(v0, v1), between(s0, s1), between(l0, l1), between(0, delay), between(al0, al1)),
    ];
  }

  /// The sparks alive [t] seconds after the burst.
  Iterable<SparkAt> at(double t) sync* {
    for (final s in sparks) {
      final age = t - s.delay;
      if (age < 0 || age >= s.life) continue;
      final p = age / s.life;
      final cx = math.cos(s.angle) * s.speed, cy = math.sin(s.angle) * s.speed;
      // Slowed by the drag: the way is v (1 - e^-dt) / d.
      final k = drag <= 0 ? age : (1 - math.exp(-drag * age)) / drag;
      final slow = drag <= 0 ? 1.0 : math.exp(-drag * age);
      final fade = (p < .08 ? p / .08 : 1.0) * math.pow(1 - p, 1.5);
      yield SparkAt(
        cx * k,
        cy * k + gravity * age * age / 2,
        cx * slow,
        cy * slow + gravity * age,
        s.size,
        s.alpha * fade,
        p,
      );
    }
  }
}
