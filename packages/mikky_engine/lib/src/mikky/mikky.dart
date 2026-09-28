import 'dart:math' as math;

import '../agents/agent.dart';
import '../anim/easing.dart';
import '../anim/keyframes.dart';
import '../anim/smoothing.dart';
import '../anim/spring.dart';

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
}

/// Shape of one eye. No pupils, ever.
enum EyeShape { oval, happy, flat, closed, tired, spiral, heart, star, slit }

enum Ear { left, right }

/// What Mikky expresses, from the agent he stands for (spec §5.2 table).
enum MikkyState { idle, working, thinking, searching, approval, question, error, finished, rateLimited, sleeping, dizzy }

/// Short expressions on top of the state.
enum MikkyEmote { love, surprised, proud, wink, yawn, content, annoyed }

/// What Mikky's body turns into. He is the sign himself, still black and
/// furry, never a perfect shape (user request, 2026-09-29).
enum MikkyForm {
  /// His usual cat silhouette.
  cat,

  /// A slightly lopsided heart (love).
  heart,

  /// A big ball of fur whose fur bristles here and there (working).
  furball,

  /// A smaller fur ball that hops (thinking).
  ball,

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

  /// Ear heights actually drawn: resting position plus flicks.
  double get earLeft => this[MikkyProp.earLeft] + this[MikkyProp.earBaseLeft];
  double get earRight => this[MikkyProp.earRight] + this[MikkyProp.earBaseRight];

  /// Body rotation actually drawn: tilt plus rolls.
  double get tilt => this[MikkyProp.tilt] + this[MikkyProp.spin];
}

/// How an expression sets eyes and ears.
class _Look {
  const _Look({
    this.left = EyeShape.oval,
    EyeShape? right,
    this.eyeScale = 1,
    this.earLeft = 0,
    double? earRight,
    this.tilt = 0,
  })  : right = right ?? left,
        earRight = earRight ?? earLeft;

  final EyeShape left, right;
  final double eyeScale, earLeft, earRight, tilt;
}

class _Particle {
  _Particle(this.kind, this.born, this.life, this.x, this.y, this.vx, this.vy, this.size, this.spin);

  final ParticleKind kind;
  final double born, life, x, y, vx, vy, size, spin;
}

/// Mikky's behaviour: states and emotes, keyframed gestures, random blinks
/// and ear flicks, breathing, gaze, head tilt, particles. Port of the
/// validated prototypes (`design/prototypes/`), itself based on Mochi's
/// `BotEngine.swift`, with ears instead of a mouth.
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
  final List<_Particle> _particles = [];

  /// Seconds since creation.
  double get time => _time;
  double _time = 0;

  /// Random offset of the breathing cycle, so two Mikky never breathe in sync.
  late final double _phase;
  late double _nextBlink;
  late double _nextTwitch;
  double _nextBeat = 0;
  double _nextEmit = 0;

  /// Approval goes round: two hops as the cat, then the "!" for 3 or 4
  /// hops, then the cat again (user request, 2026-09-29).
  bool _approvalBang = false;
  int _hopsLeft = 0;

  MikkyState _state = MikkyState.idle;
  double _dizzyUntil = -1;
  MikkyEmote? _emote;
  double _emoteUntil = 0;

  MikkyForm _form = MikkyForm.cat;

  /// Soft and bouncy, like jelly: the change overshoots a little.
  final _morph = Spring(0, const SpringSpec(95, .38));

  bool _hovered = false;
  double _lastMove = 0;
  bool _lovedThisHover = false;
  final List<double> _clicks = [];

  /// The state shown now (a triple click makes Mikky dizzy for a moment).
  MikkyState get state => _time < _dizzyUntil ? MikkyState.dizzy : _state;
  MikkyEmote? get emote => _emote;

  EyeShape get eyeLeft => _look().left;
  EyeShape get eyeRight => _look().right;

  /// The form being shown (or left, or reached): see [morph].
  MikkyForm get form => _form;

  /// How far the body has turned into [form]: 0 cat, 1 fully the form. It
  /// overshoots a little on the way, which makes it look soft.
  double get morph => _morph.value;

  /// The form the state or the emote asks for.
  MikkyForm get _wantedForm {
    final e = _emote;
    if (e != null) return e == MikkyEmote.love ? MikkyForm.heart : MikkyForm.cat;
    return switch (state) {
      MikkyState.working => MikkyForm.furball,
      MikkyState.thinking => MikkyForm.ball,
      MikkyState.approval => _approvalBang ? MikkyForm.bang : MikkyForm.cat,
      _ => MikkyForm.cat,
    };
  }

  /// States that Mikky shows by turning into a sign (even between two
  /// turns, as for approval): no badge next to him.
  static bool _showsWithForm(MikkyState s) =>
      s == MikkyState.working || s == MikkyState.thinking || s == MikkyState.approval;

  /// Sign next to the head, from the state. None when Mikky himself turns
  /// into the sign.
  MikkyBadge? get badge => _wantedForm != MikkyForm.cat || _showsWithForm(state) ? null : _stateBadge;

  MikkyBadge? get _stateBadge => switch (state) {
        MikkyState.working => const MikkyBadge(BadgeKind.dots, AgentStatus.working),
        MikkyState.thinking => const MikkyBadge(BadgeKind.dots, AgentStatus.thinking),
        MikkyState.searching => const MikkyBadge(BadgeKind.dots, AgentStatus.searching),
        MikkyState.approval => const MikkyBadge(BadgeKind.bang, AgentStatus.approval),
        MikkyState.question => const MikkyBadge(BadgeKind.question, AgentStatus.question),
        MikkyState.error => const MikkyBadge(BadgeKind.dot, AgentStatus.error),
        MikkyState.finished => const MikkyBadge(BadgeKind.dot, AgentStatus.finished),
        MikkyState.rateLimited => const MikkyBadge(BadgeKind.dot, AgentStatus.rateLimited),
        MikkyState.idle || MikkyState.sleeping || MikkyState.dizzy => null,
      };

  /// Live particles, oldest first.
  List<MikkyParticle> get particles => [
        for (final p in _particles) _particleAt(p),
      ];

  // ------------------------------------------------------------ gestures

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

  /// Click on Mikky. Three clicks within 1.7 s make him dizzy.
  void boop() {
    squash();
    blink();
    _clicks
      ..add(_time)
      ..removeWhere((t) => _time - t > 1.7);
    if (_clicks.length >= 3) {
      _clicks.clear();
      _dizzyUntil = _time + 2.6;
      roll(turns: 2, ms: 1100);
    }
  }

  /// Something needs attention: eyes widen, ears go up.
  void alert() {
    animate(MikkyProp.eyeScale, const [Keyframe(1.2, 120, Easings.back), Keyframe(1, 500, Easings.inOut)]);
    for (final prop in const [MikkyProp.earLeft, MikkyProp.earRight]) {
      animate(prop, const [Keyframe(.45, 90, Easings.out), Keyframe(0, 400, Easings.inOut)]);
    }
  }

  /// Crouch, jump, land. [small] for a little hop.
  void hop({bool small = false, double? height}) {
    final h = height ?? (small ? .12 : .3);
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

  /// Quick "no" of the head.
  void shake() {
    animate(MikkyProp.offsetX, const [
      Keyframe(.08, 60, Easings.out),
      Keyframe(-.08, 90, Easings.inOut),
      Keyframe(.06, 90, Easings.inOut),
      Keyframe(-.03, 90, Easings.inOut),
      Keyframe(0, 100, Easings.out),
    ]);
  }

  /// Whole-body roll, with a hop.
  void roll({int turns = 1, double ms = 650}) {
    animate(MikkyProp.spin, [Keyframe(math.pi * 2 * turns, ms, Easings.inOut)]);
    hop(small: true);
  }

  /// Old names of two emotes, kept for callers.
  void happy() => play(MikkyEmote.content);
  void surprised() => play(MikkyEmote.surprised);

  // ------------------------------------------------------ states, emotes

  /// Changes the state; entering some states plays a gesture.
  void setState(MikkyState s) {
    if (s == _state) return;
    _state = s;
    _nextBeat = _time + .5;
    _nextEmit = _time + .2;
    switch (s) {
      case MikkyState.approval:
        alert();
        _approvalBang = false;
        _hopsLeft = 2;
      case MikkyState.question:
        twitch(Ear.right);
      case MikkyState.error:
        shake();
      case MikkyState.finished:
        // A happy little jump, no roll.
        hop(height: .2);
        _burst(ParticleKind.sparkle, 8);
      case MikkyState.dizzy:
        roll(turns: 2, ms: 1100);
      case MikkyState.idle ||
            MikkyState.working ||
            MikkyState.thinking ||
            MikkyState.searching ||
            MikkyState.rateLimited ||
            MikkyState.sleeping:
        break;
    }
  }

  /// Plays a short expression over the state.
  void play(MikkyEmote e) {
    _emote = e;
    _nextEmit = _time;
    _emoteUntil = _time +
        switch (e) {
          MikkyEmote.love => 1.8,
          MikkyEmote.surprised => 1.2,
          MikkyEmote.proud => 1.6,
          MikkyEmote.wink => .9,
          MikkyEmote.yawn => 1.8,
          MikkyEmote.content => 1.4,
          MikkyEmote.annoyed => 1.4,
        };
    switch (e) {
      case MikkyEmote.love:
        animate(MikkyProp.eyeScale, const [Keyframe(1.12, 160, Easings.back)]);
      case MikkyEmote.surprised:
        animate(MikkyProp.eyeScale, const [Keyframe(1.25, 120, Easings.back)]);
        animate(MikkyProp.offsetY, const [Keyframe(-.15, 110, Easings.out), Keyframe(0, 260, Easings.back)]);
      case MikkyEmote.proud:
        _burst(ParticleKind.star, 6);
        hop(small: true);
      case MikkyEmote.wink:
        break;
      case MikkyEmote.yawn:
        animate(MikkyProp.scaleY, const [
          Keyframe(1.1, 500, Easings.inOut),
          Keyframe(1.1, 500, Easings.linear),
          Keyframe(1, 500, Easings.inOut),
        ]);
        animate(MikkyProp.scaleX, const [
          Keyframe(.94, 500, Easings.inOut),
          Keyframe(.94, 500, Easings.linear),
          Keyframe(1, 500, Easings.inOut),
        ]);
      case MikkyEmote.content:
        hop();
      case MikkyEmote.annoyed:
        shake();
    }
  }

  /// Eyes and ears of the emote if any, else of the state.
  _Look _look() {
    final emote = _emote;
    if (emote != null) {
      return switch (emote) {
        // He is the heart: content eyes on it.
        MikkyEmote.love => const _Look(left: EyeShape.happy, eyeScale: 1.1, earLeft: .15),
        MikkyEmote.surprised => const _Look(eyeScale: 1.25, earLeft: .45),
        MikkyEmote.proud => const _Look(left: EyeShape.star, eyeScale: 1.1, earLeft: .3),
        MikkyEmote.wink => const _Look(right: EyeShape.happy, tilt: .1, earLeft: .1),
        MikkyEmote.yawn => const _Look(left: EyeShape.closed, earLeft: -.3),
        MikkyEmote.content => const _Look(left: EyeShape.happy, earLeft: .25),
        MikkyEmote.annoyed => const _Look(left: EyeShape.slit, earLeft: -.6),
      };
    }
    return switch (state) {
      MikkyState.idle || MikkyState.working || MikkyState.searching => const _Look(),
      MikkyState.thinking => const _Look(earLeft: .05),
      MikkyState.approval => const _Look(eyeScale: 1.18, earLeft: .35),
      MikkyState.question => const _Look(eyeScale: 1.05, earLeft: -.6, earRight: .12, tilt: .17),
      MikkyState.error => const _Look(left: EyeShape.flat, earLeft: -.55),
      // Content eyes, one ear bigger than the other.
      MikkyState.finished => const _Look(left: EyeShape.happy, earLeft: .05, earRight: .6),
      MikkyState.rateLimited => const _Look(left: EyeShape.tired, earLeft: -.4),
      MikkyState.sleeping => const _Look(left: EyeShape.closed, earLeft: -.45),
      MikkyState.dizzy => const _Look(left: EyeShape.spiral),
    };
  }

  /// Where the state makes Mikky look, instead of the cursor.
  (double, double)? _stateGaze() => switch (state) {
        MikkyState.thinking => (.55, -.8),
        MikkyState.searching => (math.sin(_time * 2.4) * .9, .15),
        MikkyState.sleeping => (0, .35),
        MikkyState.dizzy => (math.cos(_time * 6) * .5, math.sin(_time * 6) * .5),
        _ => null,
      };

  // --------------------------------------------------------- interactions

  /// The cursor is over Mikky ([over]) or not. On entering: a blink.
  void hover(bool over) {
    if (over && !_hovered) {
      blink();
      _lastMove = _time;
      _lovedThisHover = false;
    }
    _hovered = over;
  }

  /// The cursor moved while over Mikky. Still for 1.9 s: love.
  void pointerMoved() => _lastMove = _time;

  // ------------------------------------------------------------ particles

  void _burst(ParticleKind kind, int count) {
    for (var i = 0; i < count; i++) {
      final a = -math.pi / 2 + (i / count - .5) * math.pi * 1.6 + (_random.nextDouble() - .5) * .3;
      final speed = 1.1 + _random.nextDouble() * .6;
      _particles.add(_Particle(kind, _time, .9 + _random.nextDouble() * .4, math.cos(a) * .7, math.sin(a) * .6 - .2,
          math.cos(a) * speed, math.sin(a) * speed, .16 + _random.nextDouble() * .08, (_random.nextDouble() - .5) * 4));
    }
  }

  void _emit() {
    final ParticleKind kind;
    final double every;
    if (_emote == MikkyEmote.love) {
      kind = ParticleKind.heart;
      every = .28;
    } else if (_emote == null && state == MikkyState.rateLimited) {
      kind = ParticleKind.sweat;
      every = 1.4;
    } else if (_emote == null && state == MikkyState.sleeping) {
      kind = ParticleKind.sleep;
      every = 1.6;
    } else {
      return;
    }
    if (_time < _nextEmit) return;
    _nextEmit = _time + every;
    final r = _random.nextDouble();
    _particles.add(switch (kind) {
      // Born above the ears, never over his face.
      ParticleKind.heart => _Particle(kind, _time, 1.3, (r - .5) * 1.6, -1.35, (r - .5) * .3, -.8, .2 + r * .08, (r - .5) * .6),
      ParticleKind.sweat => _Particle(kind, _time, 1.1, 1.05, -.55, .15, .1, .16, 0),
      ParticleKind.sleep => _Particle(kind, _time, 2, .7, -1.1, .35, -.45, .22, -.2),
      ParticleKind.sparkle || ParticleKind.star => throw StateError('bursts only'),
    });
  }

  MikkyParticle _particleAt(_Particle p) {
    final age = _time - p.born;
    final t = (age / p.life).clamp(0.0, 1.0);
    final fade = math.min(1.0, age / .15) * (t < .6 ? 1 : 1 - (t - .6) / .4);
    var y = p.y + p.vy * age;
    var x = p.x + p.vx * age;
    var size = p.size;
    switch (p.kind) {
      case ParticleKind.sweat:
        y += .9 * age * age;
      case ParticleKind.sleep:
        size *= 1 + t * .8;
        x += math.sin(age * 3) * .08;
      case ParticleKind.sparkle || ParticleKind.star:
        // Bursts slow down.
        x = p.x + p.vx * (1 - math.exp(-age * 3)) / 3 * 2;
        y = p.y + p.vy * (1 - math.exp(-age * 3)) / 3 * 2;
        size *= 1 - t * .5;
      case ParticleKind.heart:
        x += math.sin(age * 5 + p.x * 3) * .06;
    }
    return MikkyParticle(p.kind, x, y, size, fade.clamp(0.0, 1.0), p.spin * age);
  }

  // ------------------------------------------------------------------ time

  /// Advances by [dt] seconds. [lookX] and [lookY] in [-1, 1] give where
  /// Mikky looks (usually `tanh` of the cursor offset, see [lookAt]). Some
  /// states look elsewhere, unless [attention] asks to look there anyway.
  void update(double dt, {double lookX = 0, double lookY = 0, bool attention = false}) {
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
    if (_emote != null && _time > _emoteUntil) _emote = null;

    void follow(MikkyProp prop, double target, double remaining) {
      if (!isAnimating(prop)) pose[prop] = approach(pose[prop], target, remaining, dt);
    }

    final look = _look();
    final st = state;
    final gaze = attention ? null : _stateGaze();
    final (gx, gy) = gaze ?? (lookX, lookY);

    // The head follows the gaze; it tilts a little toward where it looks.
    follow(MikkyProp.yaw, gx * .5, .0025);
    follow(MikkyProp.pitch, -gy * .32, .0025);
    follow(MikkyProp.tilt, pose[MikkyProp.yaw] * .16 + look.tilt, .0008);
    if (!isAnimating(MikkyProp.spin)) pose[MikkyProp.spin] = 0;

    // Breathing, slower and deeper while asleep.
    final sleeping = st == MikkyState.sleeping;
    final breath = math.sin((_time + _phase) * (sleeping ? 1.1 : 1.8));
    follow(MikkyProp.scaleY, 1 + breath * (sleeping ? .035 : .02), .0008);
    follow(MikkyProp.scaleX, 1 - breath * (sleeping ? .025 : .014), .0008);
    follow(MikkyProp.eyeScale, look.eyeScale * (_hovered ? 1.08 : 1), .0008);

    // Ears: the expression's resting position; dizzy ones go round.
    if (st == MikkyState.dizzy && _emote == null) {
      pose[MikkyProp.earBaseLeft] = .35 * math.sin(_time * 9);
      pose[MikkyProp.earBaseRight] = .35 * math.sin(_time * 9 + math.pi);
    } else {
      follow(MikkyProp.earBaseLeft, look.earLeft, .0005);
      follow(MikkyProp.earBaseRight, look.earRight, .0005);
    }

    // Rhythm of some states.
    if (st == MikkyState.approval && _emote == null && _time > _nextBeat) {
      if (_hopsLeft > 0) {
        hop(height: .18);
        _hopsLeft--;
        _nextBeat = _time + .75;
      } else {
        // Turn into the "!" (or back), then hop again once changed.
        _approvalBang = !_approvalBang;
        _hopsLeft = _approvalBang ? 3 + _random.nextInt(2) : 2;
        _nextBeat = _time + .6;
      }
    }

    if (_hovered && !_lovedThisHover && _time - _lastMove >= 1.9) {
      _lovedThisHover = true;
      play(MikkyEmote.love);
    }

    final calm = st == MikkyState.sleeping || st == MikkyState.dizzy;
    if (_time > _nextBlink) {
      if (!calm) {
        blink();
        if (_random.nextDouble() < .22) _after(.23, blink);
      }
      _nextBlink = _time + 2.2 + _random.nextDouble() * 3.2;
    }
    if (_time > _nextTwitch) {
      if (!calm) twitch(_random.nextBool() ? Ear.left : Ear.right);
      _nextTwitch = _time + 3 + _random.nextDouble() * 5;
    }

    _updateForm(dt);
    _emit();
    _particles.removeWhere((p) => _time - p.born > p.life);
  }

  /// From one form to another, always through the cat: undo, then redo.
  void _updateForm(double dt) {
    final want = _wantedForm;
    if (want != _form) {
      if (_form == MikkyForm.cat) {
        _form = want;
      } else {
        _morph.target = 0;
        if (_morph.value.abs() < .06 && _morph.velocity.abs() < 1) _form = want;
      }
    }
    if (want == _form) _morph.target = _form == MikkyForm.cat ? 0 : 1;
    _morph.step(dt);
    if (_form == MikkyForm.cat && _morph.isAtRest(.002)) _morph.snap();
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
