import 'dart:math' as math;

/// Settings of a damped spring (unit mass).
class SpringSpec {
  const SpringSpec(this.stiffness, this.dampingRatio);

  final double stiffness;
  final double dampingRatio;

  /// The island itself: "dry" (spec §3); a little slower since 2026-10-05
  /// (« un peu trop rapide », 210 before).
  static const island = SpringSpec(165, .74);

  /// The notification drop: "sticky".
  static const drop = SpringSpec(120, .42);

  /// The split bubble.
  static const sideBubble = SpringSpec(55, .65);

  /// Mikky gliding from one place to another in the open island (from the
  /// home to an agent's page, 2026-10-05: « smooth, un peu flottant,
  /// léger, pas trop rapide »): across steady, up and down with a little
  /// float, so his way bends a bit.
  static const glideAcross = SpringSpec(60, .9);
  static const glideUpDown = SpringSpec(60, .7);

  /// Open / close progress of the island content (135 since 2026-10-05,
  /// with the island; 170 before).
  static const progress = SpringSpec(135, .8);
}

/// A damped spring toward [target], integrated like the prototypes
/// (semi-implicit Euler, 4 sub-steps per frame).
class Spring {
  Spring(this.value, this.spec) : target = value;

  final SpringSpec spec;
  double value;
  double target;
  double velocity = 0;

  void step(double dt) {
    final k = spec.stiffness;
    final c = 2 * math.sqrt(k) * spec.dampingRatio;
    const substeps = 4;
    final h = dt / substeps;
    for (var i = 0; i < substeps; i++) {
      velocity += (k * (target - value) - c * velocity) * h;
      value += velocity * h;
    }
  }

  /// True when the motion is no longer visible; [snap] then removes the rest.
  bool isAtRest([double tolerance = .01]) =>
      (value - target).abs() < tolerance && velocity.abs() < tolerance * 10;

  void snap() {
    value = target;
    velocity = 0;
  }
}
