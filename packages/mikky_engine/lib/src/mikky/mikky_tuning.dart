/// Mikky's adjustable proportions, in units of the radius R. The defaults
/// are the validated design (spec §3); the tuning screen changes them live.
class MikkyTuning {
  MikkyTuning({
    this.eyeElevation = .26,
    this.eyeSize = 1,
    this.eyeElongation = 1.25,
    this.eyeSpread = .30,
    this.bottomWiden = .055,
    this.earHeight = .55,
    this.earCenter = .60,
    this.earWidth = 1,
  });

  /// Height of the eyes on the sphere (radians).
  double eyeElevation;

  /// Scale of both eyes.
  double eyeSize;

  /// Height of the eye ovals relative to the base height .50 R.
  double eyeElongation;

  /// Angle between each eye and the middle (radians).
  double eyeSpread;

  /// How much wider the bottom is than the top.
  double bottomWiden;

  /// Height of the ears (× R).
  double earHeight;

  /// Position of the ears (× half width).
  double earCenter;

  /// Width of the ears (× the validated width).
  double earWidth;

  static final defaults = MikkyTuning();

  MikkyTuning copy() => MikkyTuning.fromJson(toJson());

  Map<String, double> toJson() => {
        'eyeElevation': eyeElevation,
        'eyeSize': eyeSize,
        'eyeElongation': eyeElongation,
        'eyeSpread': eyeSpread,
        'bottomWiden': bottomWiden,
        'earHeight': earHeight,
        'earCenter': earCenter,
        'earWidth': earWidth,
      };

  /// Unknown or missing keys keep their default.
  factory MikkyTuning.fromJson(Map<String, Object?> json) {
    double v(String key, double fallback) => (json[key] as num?)?.toDouble() ?? fallback;
    final d = MikkyTuning();
    return MikkyTuning(
      eyeElevation: v('eyeElevation', d.eyeElevation),
      eyeSize: v('eyeSize', d.eyeSize),
      eyeElongation: v('eyeElongation', d.eyeElongation),
      eyeSpread: v('eyeSpread', d.eyeSpread),
      bottomWiden: v('bottomWiden', d.bottomWiden),
      earHeight: v('earHeight', d.earHeight),
      earCenter: v('earCenter', d.earCenter),
      earWidth: v('earWidth', d.earWidth),
    );
  }
}
