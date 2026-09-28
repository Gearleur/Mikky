import 'dart:math' as math;

import '../anim/easing.dart';
import '../anim/keyframes.dart';
import '../anim/smoothing.dart';

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

  /// Eye scale (surprise).
  eyeScale,

  /// Ear twitch, left and right: > 0 raised, < 0 lowered.
  earLeft,
  earRight,

  /// Whole body rotation (radians).
  tilt,
}

enum EyeShape { oval, happy }

enum Ear { left, right }

/// Mikky's pose, one value per [MikkyProp].
class MikkyPose {
  final List<double> _values = [
    for (final prop in MikkyProp.values) _rest(prop),
  ];

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
  double get earLeft => this[MikkyProp.earLeft];
  double get earRight => this[MikkyProp.earRight];
  double get tilt => this[MikkyProp.tilt];
}

/// Mikky's behaviour: keyframed gestures, random blinks and ear twitches,
/// breathing, gaze and head tilt. Port of the validated prototypes
/// (`design/prototypes/`), itself based on Mochi's `BotEngine.swift`.
///
/// Time only moves through [update], so tests can drive it frame by frame.
class Mikky {
  Mikky({math.Random? random}) : _random = random ?? math.Random() {
    _phase = _random.nextDouble() * 5;
    _nextBlink = 1 + _random.nextDouble() * 2;
    _nextTwitch = 3;
  }

  final math.Random _random;
  final pose = MikkyPose();
  final Map<MikkyProp, KeyframeTrack> _tracks = {};
  final List<(double, void Function())> _scheduled = [];

  /// Seconds since creation.
  double get time => _time;
  double _time = 0;

  /// Random offset of the breathing cycle, so two Mikky never breathe in sync.
  late final double _phase;
  late double _nextBlink;
  late double _nextTwitch;
  double _expressionUntil = 0;

  EyeShape get eyes => _eyes;
  EyeShape _eyes = EyeShape.oval;

  /// Plays [keys] on [prop], from its current value, replacing any running
  /// animation of that property.
  void animate(MikkyProp prop, List<Keyframe> keys) {
    _tracks[prop] = KeyframeTrack(keys, from: pose[prop], start: _time);
  }

  bool isAnimating(MikkyProp prop) => _tracks.containsKey(prop);

  void _after(double seconds, void Function() action) => _scheduled.add((_time + seconds, action));

  void blink() => animate(MikkyProp.open, const [
        Keyframe(.06, 70, Easings.inOut),
        Keyframe(1, 130, Easings.out),
      ]);

  /// One ear flicks; both when [ear] is null (the right one slightly later).
  void twitch([Ear? ear]) {
    const keys = [
      Keyframe(.35, 90, Easings.out),
      Keyframe(-.12, 120, Easings.inOut),
      Keyframe(0, 160, Easings.out),
    ];
    if (ear != Ear.right) animate(MikkyProp.earLeft, keys);
    if (ear == Ear.right) animate(MikkyProp.earRight, keys);
    if (ear == null) _after(.06, () => animate(MikkyProp.earRight, keys));
  }

  void squash() {
    animate(MikkyProp.scaleY, const [
      Keyframe(.8, 70, Easings.out),
      Keyframe(1.1, 130, Easings.out),
      Keyframe(1, 170, Easings.inOut),
    ]);
    animate(MikkyProp.scaleX, const [
      Keyframe(1.14, 70, Easings.out),
      Keyframe(.95, 130, Easings.out),
      Keyframe(1, 170, Easings.inOut),
    ]);
  }

  /// Click on Mikky.
  void boop() {
    squash();
    blink();
  }

  /// Something needs attention: eyes widen, ears go up.
  void alert() {
    animate(MikkyProp.eyeScale, const [Keyframe(1.2, 120, Easings.back), Keyframe(1, 500, Easings.inOut)]);
    for (final prop in const [MikkyProp.earLeft, MikkyProp.earRight]) {
      animate(prop, const [Keyframe(.45, 90, Easings.out), Keyframe(0, 400, Easings.inOut)]);
    }
  }

  /// Crouch, jump, land. [small] for a little hop.
  void hop({bool small = false}) {
    final h = small ? .12 : .3;
    animate(MikkyProp.scaleY, const [
      Keyframe(.88, 90, Easings.out),
      Keyframe(1.14, 120, Easings.out),
      Keyframe(1, 180, Easings.inOut),
      Keyframe(.86, 70, Easings.out),
      Keyframe(1, 200, Easings.back),
    ]);
    animate(MikkyProp.scaleX, const [
      Keyframe(1.1, 90, Easings.out),
      Keyframe(.92, 120, Easings.out),
      Keyframe(1, 180, Easings.inOut),
      Keyframe(1.12, 70, Easings.out),
      Keyframe(1, 200, Easings.back),
    ]);
    animate(MikkyProp.offsetY, [
      const Keyframe(.04, 90, Easings.out),
      Keyframe(-h, 200, Easings.out),
      const Keyframe(0, 200, Easings.inOut),
    ]);
  }

  /// Happy arcs for the eyes, a hop, ears slightly up.
  void happy() {
    _eyes = EyeShape.happy;
    _expressionUntil = _time + 1.4;
    hop();
    animate(MikkyProp.earLeft, const [Keyframe(.25, 120, Easings.out)]);
    animate(MikkyProp.earRight, const [Keyframe(.25, 120, Easings.out)]);
  }

  void surprised() {
    _expressionUntil = _time + 1.2;
    animate(MikkyProp.eyeScale, const [Keyframe(1.25, 120, Easings.back)]);
    animate(MikkyProp.offsetY, const [Keyframe(-.15, 110, Easings.out), Keyframe(0, 260, Easings.back)]);
    animate(MikkyProp.earLeft, const [Keyframe(.45, 90, Easings.out)]);
    animate(MikkyProp.earRight, const [Keyframe(.45, 90, Easings.out)]);
  }

  /// Advances by [dt] seconds. [lookX] and [lookY] in [-1, 1] give where
  /// Mikky looks (usually `tanh` of the cursor offset, see [lookAt]).
  void update(double dt, {double lookX = 0, double lookY = 0}) {
    _time += dt;

    for (final entry in _tracks.entries.toList()) {
      pose[entry.key] = entry.value.sample(_time);
      if (entry.value.isDone) _tracks.remove(entry.key);
    }
    if (_scheduled.isNotEmpty) {
      final due = _scheduled.where((s) => s.$1 <= _time).toList();
      _scheduled.removeWhere((s) => s.$1 <= _time);
      for (final s in due) {
        s.$2();
      }
    }

    void follow(MikkyProp prop, double target, double remaining) {
      if (!isAnimating(prop)) pose[prop] = approach(pose[prop], target, remaining, dt);
    }

    // The head follows the gaze; it tilts a little toward where it looks.
    follow(MikkyProp.yaw, lookX * .5, .0025);
    follow(MikkyProp.pitch, -lookY * .32, .0025);
    follow(MikkyProp.tilt, pose.yaw * .16, .0008);
    // Breathing.
    final breath = math.sin((_time + _phase) * 1.8);
    follow(MikkyProp.scaleY, 1 + breath * .02, .0008);
    follow(MikkyProp.scaleX, 1 - breath * .014, .0008);
    follow(MikkyProp.eyeScale, 1, .0008);

    if (_expressionUntil > 0 && _time > _expressionUntil) {
      _expressionUntil = 0;
      _eyes = EyeShape.oval;
      for (final prop in const [MikkyProp.earLeft, MikkyProp.earRight]) {
        if (!isAnimating(prop)) animate(prop, const [Keyframe(0, 200, Easings.inOut)]);
      }
    }

    if (_time > _nextBlink) {
      blink();
      if (_random.nextDouble() < .22) _after(.23, blink);
      _nextBlink = _time + 2.2 + _random.nextDouble() * 3.2;
    }
    if (_time > _nextTwitch) {
      twitch(_random.nextBool() ? Ear.left : Ear.right);
      _nextTwitch = _time + 3 + _random.nextDouble() * 5;
    }
  }

  /// Gaze input for a target at ([dx], [dy]) pixels from Mikky's center.
  static (double, double) lookAt(double dx, double dy) => (_tanh(dx / 260), _tanh(dy / 200));
}

double _tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
