import 'dart:math' as math;

/// Settings of a damped spring (unit mass).
class SpringSpec {
  const SpringSpec(this.stiffness, this.dampingRatio);

  final double stiffness;
  final double dampingRatio;

  /// The island itself: "dry" (spec §3).
  static const island = SpringSpec(210, .74);

  /// The notification drop: "sticky".
  static const drop = SpringSpec(120, .42);

  /// The split bubble.
  static const sideBubble = SpringSpec(150, .5);

  /// Open / close progress of the island content.
  static const progress = SpringSpec(170, .8);
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
