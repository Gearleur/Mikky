import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import 'launch.dart';

/// Mikky's entrance (2026-10-06: « plus simple, plus smooth, plus animé…
/// une intro à la Disney, une petite apparition à la Pixar, vraiment
/// simple, sur un fond blanc avec une petite ombre »): on a white stage,
/// his shadow on the ground, the classic principles — anticipation,
/// squash and stretch, arcs, ears that follow late.
///
/// Tracks: `x` from the middle and `h` above the ground (units of his
/// radius); `size` how big he is (popping in); `shadow` how much of his
/// shadow there is; the [MikkyProp] names, his pose; `happy`, `closed`
/// his eyes.
abstract final class Intros {
  static final all = [hops, pop, drop];

  /// Hops in from the side, like Pixar's lamp: three hops, smaller and
  /// smaller, a squash at each landing, ears late; then he turns to us,
  /// blinks, and smiles with his eyes.
  static final hops = Choreography(
    name: 'Les sauts',
    duration: 3.8,
    marks: const [Mark(0, 'entre'), Mark(.62, 'saut'), Mark(1.12, 'saut'), Mark(1.56, 'pose'), Mark(2.1, 'nous regarde'), Mark(2.8, 'content')],
    tracks: {
      'x': const [Beat(0, 8.5), Beat(.12, 8.5), Beat(.62, 5.4, Easings.linear), Beat(1.12, 2.4, Easings.linear), Beat(1.56, 0, Easings.out)],
      'h': [
        ..._hop(.12, .62, 1.3),
        ..._hop(.62, 1.12, .9),
        ..._hop(1.12, 1.56, .5),
      ],
      'scaleY': [..._squash(.12, .62, true), ..._squash(.62, 1.12, false), ..._squash(1.12, 1.56, false, last: true)],
      'scaleX': [..._squash(.12, .62, true, x: true), ..._squash(.62, 1.12, false, x: true), ..._squash(1.12, 1.56, false, x: true, last: true)],
      // He leans into the way he goes, then stands up.
      'tilt': const [Beat(0, 0), Beat(.2, -.14), Beat(1.5, -.1), Beat(1.8, .04, Easings.out), Beat(2.05, 0)],
      'yaw': const [Beat(0, -.5), Beat(1.9, -.5), Beat(2.25, 0, Easings.inOut)],
      'earLeft': [..._ears(.12, 1.56), const Beat(2.8, 0), ...Choreography.wiggle(2.8, 3.4, 0, .5, 2)],
      'earRight': [..._ears(.16, 1.6), const Beat(2.88, 0), ...Choreography.wiggle(2.88, 3.48, 0, .5, 2)],
      'open': const [Beat(2.35, 1), Beat(2.42, .06), Beat(2.55, 1, Easings.out)],
      'happy': const [Beat(2.8, 0), Beat(2.81, 1, Easings.linear)],
    },
  );

  /// Pops up from his shadow: the shadow first, then him, overshooting a
  /// little and settling, eyes shut, then open; ears flop late; a curious
  /// tilt, and a small happy hop.
  static final pop = Choreography(
    name: 'Le pop',
    duration: 3.0,
    marks: const [Mark(0, 'l’ombre'), Mark(.32, 'pop'), Mark(.9, 'ouvre les yeux'), Mark(1.4, 'curieux'), Mark(2.2, 'content')],
    tracks: {
      'shadow': const [Beat(0, 0), Beat(.32, 1, Easings.out)],
      'size': [const Beat(.3, 0), Beat(.85, 1, Easings.spring(const SpringSpec(240, .42), .55))],
      'h': const [Beat(.3, 0), Beat(.52, .45, Easings.out), Beat(.72, 0, Easings.inCubic), Beat(2.2, 0), Beat(2.38, .35, Easings.out), Beat(2.56, 0, Easings.inCubic)],
      'scaleY': [
        const Beat(.3, 1.2),
        const Beat(.72, 1.12),
        const Beat(.78, .8, Easings.out),
        Beat(1.1, 1, Easings.spring(const SpringSpec(260, .4), .32)),
        const Beat(2.14, 1),
        const Beat(2.2, .88, Easings.out),
        const Beat(2.38, 1.06),
        const Beat(2.6, .9, Easings.out),
        Beat(2.85, 1, Easings.spring(const SpringSpec(260, .45), .25)),
      ],
      'scaleX': [
        const Beat(.3, .85),
        const Beat(.72, .9),
        const Beat(.78, 1.18, Easings.out),
        Beat(1.1, 1, Easings.spring(const SpringSpec(260, .4), .32)),
        const Beat(2.14, 1),
        const Beat(2.2, 1.1, Easings.out),
        const Beat(2.38, .95),
        const Beat(2.6, 1.1, Easings.out),
        Beat(2.85, 1, Easings.spring(const SpringSpec(260, .45), .25)),
      ],
      'open': const [Beat(.3, .08), Beat(.88, .08), Beat(1.0, 1, Easings.out)],
      'eyeScale': const [Beat(.9, 1), Beat(1.05, 1.15, Easings.back), Beat(1.4, 1)],
      'earLeft': [const Beat(.3, -.6), const Beat(.8, -.6), Beat(1.25, 0, Easings.spring(const SpringSpec(180, .35), .45))],
      'earRight': [const Beat(.3, -.6), const Beat(.86, -.6), Beat(1.31, 0, Easings.spring(const SpringSpec(180, .35), .45))],
      'tilt': const [Beat(1.4, 0), Beat(1.65, .2, Easings.inOut), Beat(1.95, .2), Beat(2.15, 0, Easings.inOut)],
      'yaw': const [Beat(1.4, 0), Beat(1.65, .3, Easings.inOut), Beat(1.95, .3), Beat(2.15, 0, Easings.inOut)],
      'happy': const [Beat(2.2, 0), Beat(2.21, 1, Easings.linear)],
    },
  );

  /// Drops softly from above: his shadow grows under him, he stretches as
  /// he falls, squashes on landing, bounces once, ears flop and come back;
  /// he looks at us, blinks, smiles.
  static final drop = Choreography(
    name: 'La douce chute',
    duration: 3.2,
    marks: const [Mark(0, 'tombe'), Mark(.7, 'atterrit'), Mark(1.25, 'se pose'), Mark(1.7, 'nous regarde'), Mark(2.4, 'content')],
    tracks: {
      'h': const [Beat(0, 7), Beat(.7, 0, Easings.inCubic), Beat(1.02, .55, Easings.out), Beat(1.25, 0, Easings.inCubic)],
      'scaleY': [
        const Beat(0, 1),
        const Beat(.62, 1.2, Easings.inCubic),
        const Beat(.74, .72, Easings.out),
        const Beat(.92, 1.08, Easings.out),
        const Beat(1.2, 1),
        const Beat(1.28, .88, Easings.out),
        Beat(1.55, 1, Easings.spring(const SpringSpec(240, .45), .27)),
      ],
      'scaleX': [
        const Beat(0, 1),
        const Beat(.62, .86, Easings.inCubic),
        const Beat(.74, 1.26, Easings.out),
        const Beat(.92, .95, Easings.out),
        const Beat(1.2, 1),
        const Beat(1.28, 1.1, Easings.out),
        Beat(1.55, 1, Easings.spring(const SpringSpec(240, .45), .27)),
      ],
      // The air lifts his ears while he falls; they flop when he lands.
      'earLeft': [const Beat(0, .6), const Beat(.7, .6), const Beat(.8, -.5, Easings.out), Beat(1.3, 0, Easings.spring(const SpringSpec(180, .35), .5)), const Beat(2.4, 0), ...Choreography.wiggle(2.4, 3.0, 0, .5, 2)],
      'earRight': [const Beat(0, .6), const Beat(.74, .6), const Beat(.84, -.5, Easings.out), Beat(1.34, 0, Easings.spring(const SpringSpec(180, .35), .5)), const Beat(2.46, 0), ...Choreography.wiggle(2.46, 3.06, 0, .5, 2)],
      'closed': const [Beat(.72, 0), Beat(.73, 1, Easings.linear), Beat(.98, 1), Beat(.99, 0, Easings.linear)],
      'pitch': const [Beat(0, -.25), Beat(.7, -.25), Beat(1.0, 0, Easings.out), Beat(1.7, 0), Beat(1.9, .1, Easings.inOut), Beat(2.4, .1)],
      'open': const [Beat(1.95, 1), Beat(2.02, .06), Beat(2.15, 1, Easings.out)],
      'happy': const [Beat(2.4, 0), Beat(2.41, 1, Easings.linear)],
    },
  );

  /// One hop from [from] to [to], [height] high: up on an ease out, down
  /// on an ease in (an arc, as it falls).
  static List<Beat> _hop(double from, double to, double height) {
    final crouch = from + .08, peak = crouch + (to - crouch) * .48;
    return [Beat(from, 0), Beat(crouch, 0), Beat(peak, height, Easings.out), Beat(to, 0, Easings.inCubic)];
  }

  /// The squash and stretch of a hop: a crouch before (only the first:
  /// [first]; the others start from the last landing), stretched going up,
  /// round at the top, squashed on landing; [last] settles after it.
  static List<Beat> _squash(double from, double to, bool first, {bool x = false, bool last = false}) {
    double v(double y) => x ? 2 - y : y;
    final crouch = from + .08, peak = crouch + (to - crouch) * .48;
    return [
      if (first) Beat(from, 1),
      Beat(crouch, v(.84), Easings.out),
      Beat(crouch + .08, v(1.14), Easings.out),
      Beat(peak, 1),
      Beat(to - .04, v(1.08)),
      Beat(to + .06, v(.82), Easings.out),
      if (last) Beat(to + .4, 1, Easings.spring(const SpringSpec(240, .45), .34)),
    ];
  }

  /// Ears that follow the hops late: down as he goes up, up as he lands.
  static List<Beat> _ears(double from, double to) => [
        Beat(from, 0),
        Beat(from + .16, -.45, Easings.out),
        Beat(from + .42, .4, Easings.inOut),
        Beat(from + .66, -.35, Easings.inOut),
        Beat(from + .92, .35, Easings.inOut),
        Beat(from + 1.16, -.25, Easings.inOut),
        Beat(to + .16, .3, Easings.inOut),
        Beat(to + .6, 0, Easings.spring(const SpringSpec(180, .35), .44)),
      ];
}

/// A white stage at the instant [t] of an intro: the ground (unseen), his
/// soft shadow on it, him.
class IntroScene extends StatelessWidget {
  const IntroScene(this.choreography, this.t, {super.key, this.size = const Size(520, 220), this.radius = 34});

  final Choreography choreography;
  final double t;
  final Size size;
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(size: size, painter: _IntroPainter(choreography, t, radius));
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.c, this.t, this.radius);

  final Choreography c;
  final double t;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    // White, a touch warm at the bottom, like a lit floor.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFFFF), Color(0xFFF6F6F4)])
            .createShader(Offset.zero & size),
    );
    final r = radius;
    final grow = c.value('size', t, 1);
    if (grow <= .01) {
      _shadow(canvas, size, Offset(size.width / 2, size.height * .8), 0, 1, c.value('shadow', t, 1));
      return;
    }
    final ground = size.height * .8;
    final h = c.value('h', t);
    final sy = c.value('scaleY', t, 1);
    final x = size.width / 2 + c.value('x', t) * r;
    // His bottom on the ground, however squashed.
    final y = ground - MikkyShape.halfHeight * r * sy * grow - h * r;
    _shadow(canvas, size, Offset(x, ground), h, grow, c.value('shadow', t, 1));
    MikkyPainter(
      geometry: geometryAt(c, t, r * grow),
      center: Offset(x, y),
      statusColor: MikkyTheme.light.status,
      foreground: MikkyTheme.light.foreground,
      showBadge: false,
    ).paint(canvas, size);
  }

  /// His shadow: smaller and paler the higher he is.
  void _shadow(Canvas canvas, Size size, Offset at, double h, double grow, double amount) {
    if (amount <= 0) return;
    final far = math.min(h / 5, 1.0);
    final w = radius * 2.1 * grow.clamp(.35, 1.0) * (1 - .55 * far) * amount;
    canvas.drawOval(
      Rect.fromCenter(center: at + const Offset(0, 2), width: w, height: w * .2),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, .2 * (1 - .6 * far) * amount)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .12),
    );
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.t != t || old.c != c || old.radius != radius;
}
