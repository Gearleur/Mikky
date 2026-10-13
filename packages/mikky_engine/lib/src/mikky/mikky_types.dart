import '../agents/agent.dart';

/// Animated properties of Mikky's pose.
enum MikkyProp {
  /// Head rotation, left/right (radians on the eye sphere).
  yaw,

  /// Head rotation, up/down.
  pitch,

  /// Eyelids: 1 open, ~0 closed.
  open,

  /// Body scale (squash and stretch, breathing).
  scaleX,
  scaleY,

  /// Body offset, in units of Mikky's radius (hops, shakes).
  offsetX,
  offsetY,

  /// Eye scale (surprise, approval, hover).
  eyeScale,

  /// Quick ear flicks, left and right: > 0 raised, < 0 lowered.
  earLeft,
  earRight,

  /// Resting ear position of the current expression, same scale.
  earBaseLeft,
  earBaseRight,

  /// Head tilt (radians).
  tilt,

  /// Rolls: whole turns, back to 0 when done.
  spin,

  /// His arms (a trial, 2026-10-06: « des bras plutôt » than paws; the
  /// melted stumps kept): 0 melted into his body, out of sight; 1 out of
  /// his sides.
  arms,

  /// How far each arm is raised, turned from its shoulder (radians, up
  /// > 0; it stays where it grows out of him, never slides up).
  armLeftLift,
  armRightLift,

  /// How much longer each arm gets (0: as at rest; 0.2: a fifth longer,
  /// hardly thicker), when raised or reaching.
  armLeftGrow,
  armRightGrow,
}

/// Shape of one eye. No pupils, ever. [round]: big round eyes (surprise).
enum EyeShape { oval, round, happy, flat, closed, tired, spiral, heart, star, slit }

enum Ear { left, right }

/// What Mikky expresses, from the agent he stands for.
enum MikkyState {
  idle,
  working,
  thinking,
  searching,
  approval,
  question,
  error,
  finished,
  rateLimited,
  sleeping,
  dizzy,
}

/// Short expressions on top of the state.
enum MikkyEmote { love, surprised, proud, wink, yawn, content, annoyed }

/// What Mikky's body turns into. He is the sign himself, still black and
/// furry, never a perfect shape (user request, 2026-09-29).
enum MikkyForm {
  /// His usual cat silhouette.
  cat,

  /// Himself, a little squeezed into a heart (love).
  heart,

  /// Himself without ears, his fur standing out a little more all around:
  /// a ball of fur. Not used for now (thinking is himself again).
  furball,

  /// The bar of a "!", without eyes; a little fur ball below, well apart,
  /// is the dot (approval).
  bang,
}

/// Small sign next to Mikky's head.
enum BadgeKind {
  /// "•••", animated.
  dots,

  /// "!"
  bang,

  /// "?"
  question,

  /// Plain colored dot.
  dot,
}

class MikkyBadge {
  const MikkyBadge(this.kind, this.color);

  final BadgeKind kind;

  /// Status whose theme color the badge takes.
  final AgentStatus color;
}

enum ParticleKind { sparkle, heart, star, sweat, sleep }

/// One particle at one instant, in units of R from Mikky's center (y down).
class MikkyParticle {
  const MikkyParticle(this.kind, this.x, this.y, this.size, this.alpha, this.rotation);

  final ParticleKind kind;
  final double x, y, size, alpha, rotation;
}

/// Mikky's pose, one value per [MikkyProp].
class MikkyPose {
  final List<double> _values = [for (final prop in MikkyProp.values) _rest(prop)];

  static double _rest(MikkyProp prop) => switch (prop) {
    MikkyProp.open || MikkyProp.scaleX || MikkyProp.scaleY || MikkyProp.eyeScale => 1,
    _ => 0,
  };

  double operator [](MikkyProp prop) => _values[prop.index];
  void operator []=(MikkyProp prop, double value) => _values[prop.index] = value;

  double get yaw => this[MikkyProp.yaw];
  double get pitch => this[MikkyProp.pitch];
  double get open => this[MikkyProp.open];
  double get scaleX => this[MikkyProp.scaleX];
  double get scaleY => this[MikkyProp.scaleY];
  double get offsetX => this[MikkyProp.offsetX];
  double get offsetY => this[MikkyProp.offsetY];
  double get eyeScale => this[MikkyProp.eyeScale];

  /// Ear heights actually drawn: resting position plus flicks.
  double get earLeft => this[MikkyProp.earLeft] + this[MikkyProp.earBaseLeft];
  double get earRight => this[MikkyProp.earRight] + this[MikkyProp.earBaseRight];

  /// Body rotation actually drawn: tilt plus rolls.
  double get tilt => this[MikkyProp.tilt] + this[MikkyProp.spin];
}
