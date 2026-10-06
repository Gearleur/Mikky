import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../island/island_painter.dart';
import '../mikky/mikky_painter.dart';
import '../theme.dart';
import '../ui/pixel_fx.dart';
import '../ui/tokens.dart';

/// Mikky's greeting when the app starts (2026-10-05, « un meilleur
/// launch »): trials, each a [Choreography] written by hand, played in a
/// [LaunchScene]. The island comes out of the top of the screen, Mikky
/// arrives in it, says hello, and both go away.
///
/// Tracks: `iw`, `ih` the island (px); `x`, `y` Mikky's center from the
/// island's top middle (px); the [MikkyProp] names, his pose; `happy`,
/// `closed` his eyes (above 0.5); `furball` how much he is a fur ball.
/// Marks: what happens, and where particles start.
abstract final class Launches {
  /// The island while it greets, and Mikky's place in it.
  static const width = 340.0, height = 116.0, restY = 62.0, radius = 27.0;

  static final all = [fall, hatch, arms];

  static List<Beat> _islandIn(String track, double to) => [Beat(0, track == 'iw' ? 150 : 0), Beat(.5, to, Easings.back)];

  static List<Beat> _islandOut(double at, String track) => [Beat(at, track == 'iw' ? width : height), Beat(at + .55, track == 'iw' ? 150 : 0, Easings.inOut)];

  /// Hello with the ears: both flick, one after the other, three times.
  static Map<String, List<Beat>> _earHello(double from, double to) => {
        'earLeft': [Beat(from - .01, 0), ...Choreography.wiggle(from, to, 0, .7, 3)],
        'earRight': [Beat(from + .07, 0), ...Choreography.wiggle(from + .08, to + .08, 0, .7, 3)],
      };

  /// « La chute »: like Mochi, he falls in from the top of the screen,
  /// lands squashed in a ring of dust, bounces, looks around, says hello
  /// with his ears.
  static final fall = Choreography(
    name: 'La chute',
    duration: 5.3,
    marks: const [Mark(0, 'l’île sort'), Mark(.3, 'il tombe'), Mark(.68, 'atterrit'), Mark(1.6, 'regarde'), Mark(3.2, 'coucou'), Mark(4.6, 'repart')],
    tracks: {
      'iw': [..._islandIn('iw', width), ..._islandOut(4.7, 'iw')],
      'ih': [..._islandIn('ih', height), ..._islandOut(4.7, 'ih')],
      'y': const [
        Beat(.3, -50),
        Beat(.68, restY + 9, Easings.inCubic),
        Beat(.94, restY - 22, Easings.out),
        Beat(1.16, restY + 2, Easings.inCubic),
        Beat(1.36, restY, Easings.out),
        Beat(4.6, restY),
        Beat(5.15, restY + 95, Easings.inCubic),
      ],
      'scaleY': [
        const Beat(.3, 1),
        const Beat(.62, 1.24, Easings.inCubic),
        const Beat(.72, .7, Easings.out),
        const Beat(.92, 1.1, Easings.out),
        const Beat(1.14, 1),
        const Beat(1.2, .88, Easings.out),
        Beat(1.55, 1, Easings.spring(const SpringSpec(260, .4), .35)),
      ],
      'scaleX': [
        const Beat(.3, 1),
        const Beat(.62, .84, Easings.inCubic),
        const Beat(.72, 1.28, Easings.out),
        const Beat(.92, .93, Easings.out),
        const Beat(1.14, 1),
        const Beat(1.2, 1.1, Easings.out),
        Beat(1.55, 1, Easings.spring(const SpringSpec(260, .4), .35)),
      ],
      'open': const [Beat(.66, 1), Beat(.7, .12, Easings.out), Beat(1.0, 1, Easings.out), Beat(1.95, 1), Beat(2.02, .06), Beat(2.15, 1, Easings.out)],
      'yaw': const [Beat(1.6, 0), Beat(1.95, -.55), Beat(2.35, -.55), Beat(2.8, .55), Beat(3.05, .55), Beat(3.3, 0)],
      'pitch': const [Beat(3.2, 0), Beat(3.4, .12), Beat(4.3, .12), Beat(4.6, 0)],
      'tilt': [const Beat(3.2, 0), ...Choreography.wiggle(3.25, 4.3, 0, .12, 3)],
      'happy': const [Beat(3.2, 0), Beat(3.21, 1, Easings.linear), Beat(4.3, 1), Beat(4.31, 0, Easings.linear)],
      ..._earHello(3.3, 4.2),
    },
  );

  /// « L'éclosion »: a little fur ball spins into the island, quivers,
  /// and pops into Mikky among pixel sparks; he opens his eyes, his ears
  /// spring up one after the other, he looks, says hello with a hop.
  static final hatch = Choreography(
    name: 'L’éclosion',
    duration: 5.6,
    marks: const [Mark(0, 'l’île sort'), Mark(.25, 'une boule'), Mark(1.2, 'éclot'), Mark(1.5, 'ouvre les yeux'), Mark(3.2, 'coucou'), Mark(4.8, 'repart')],
    tracks: {
      'iw': [..._islandIn('iw', width), ..._islandOut(4.9, 'iw')],
      'ih': [..._islandIn('ih', height), ..._islandOut(4.9, 'ih')],
      'y': const [Beat(0, restY + 4), Beat(3.3, restY), Beat(3.5, restY - 16, Easings.out), Beat(3.72, restY, Easings.inCubic), Beat(4.8, restY), Beat(5.35, restY + 95, Easings.inCubic)],
      'furball': [const Beat(1.2, 1), Beat(1.65, 0, Easings.spring(const SpringSpec(95, .38), .45))],
      'scaleX': [
        const Beat(.25, 0),
        const Beat(.75, .5, Easings.back),
        const Beat(1.2, .5),
        const Beat(1.32, 1.14, Easings.out),
        Beat(1.7, 1, Easings.spring(const SpringSpec(220, .38), .38)),
        const Beat(3.3, 1),
        const Beat(3.36, 1.08, Easings.out),
        const Beat(3.5, .94),
        const Beat(3.72, 1.1, Easings.out),
        const Beat(3.9, 1),
      ],
      'scaleY': [
        const Beat(.25, 0),
        const Beat(.75, .5, Easings.back),
        const Beat(1.2, .5),
        const Beat(1.32, 1.1, Easings.out),
        Beat(1.7, 1, Easings.spring(const SpringSpec(220, .38), .38)),
        const Beat(3.3, 1),
        const Beat(3.36, .9, Easings.out),
        const Beat(3.5, 1.08),
        const Beat(3.72, .88, Easings.out),
        const Beat(3.9, 1),
      ],
      'tilt': [const Beat(.25, -2.2), const Beat(1.0, 0, Easings.out), ...Choreography.wiggle(3.9, 4.6, 0, .1, 2)],
      'offsetX': [const Beat(.85, 0), ...Choreography.wiggle(.85, 1.18, 0, .06, 4)],
      'open': const [Beat(1.5, .08), Beat(1.7, 1, Easings.out), Beat(2.4, 1), Beat(2.47, .06), Beat(2.6, 1, Easings.out)],
      'eyeScale': const [Beat(1.6, 1), Beat(1.8, 1.16, Easings.back), Beat(2.9, 1.16), Beat(3.2, 1)],
      'yaw': const [Beat(2.0, 0), Beat(2.3, -.4), Beat(2.55, -.4), Beat(2.85, .4), Beat(3.0, .4), Beat(3.2, 0)],
      'earLeft': [const Beat(1.3, -.6), const Beat(1.45, .9, Easings.back), const Beat(1.75, 0), const Beat(3.7, 0), ...Choreography.wiggle(3.75, 4.55, 0, .6, 3)],
      'earRight': [const Beat(1.42, -.6), const Beat(1.6, .9, Easings.back), const Beat(1.9, 0), const Beat(3.8, 0), ...Choreography.wiggle(3.83, 4.63, 0, .6, 3)],
      'happy': const [Beat(3.3, 0), Beat(3.31, 1, Easings.linear), Beat(4.6, 1), Beat(4.61, 0, Easings.linear)],
    },
  );

  /// « Les bras »: he climbs up from the bottom of the island: his ears
  /// first, then his eyes, he looks around; his hands grab the edge, he
  /// pulls himself up, and waves.
  static final arms = Choreography(
    name: 'Les bras',
    duration: 6.3,
    marks: const [
      Mark(0, 'l’île sort'),
      Mark(.95, 'les oreilles'),
      Mark(1.9, 'les yeux'),
      Mark(3.0, 'les mains'),
      Mark(3.3, 'se hisse'),
      Mark(3.85, 'atterrit'),
      Mark(4.1, 'coucou'),
      Mark(5.6, 'repart'),
    ],
    tracks: {
      'iw': [..._islandIn('iw', width), ..._islandOut(5.7, 'iw')],
      'ih': [..._islandIn('ih', height), ..._islandOut(5.7, 'ih')],
      'y': const [
        Beat(.6, 152),
        Beat(.95, 124, Easings.out),
        Beat(1.6, 124),
        Beat(1.9, 104, Easings.inOut),
        Beat(3.25, 104),
        Beat(3.36, 110, Easings.out),
        Beat(3.66, restY - 18, Easings.out),
        Beat(3.85, restY + 3, Easings.inCubic),
        Beat(4.0, restY, Easings.out),
        Beat(5.6, restY),
        Beat(6.15, restY + 95, Easings.inCubic),
      ],
      'scaleY': const [Beat(3.3, 1), Beat(3.36, .9, Easings.out), Beat(3.55, 1.16, Easings.out), Beat(3.75, 1), Beat(3.87, .82, Easings.out), Beat(4.1, 1, Easings.back)],
      'scaleX': const [Beat(3.3, 1), Beat(3.36, 1.08, Easings.out), Beat(3.55, .9, Easings.out), Beat(3.75, 1), Beat(3.87, 1.16, Easings.out), Beat(4.1, 1, Easings.back)],
      'earLeft': [const Beat(1.15, 0), ...Choreography.wiggle(1.15, 1.45, 0, .5, 1)],
      'earRight': [const Beat(1.3, 0), ...Choreography.wiggle(1.3, 1.6, 0, .5, 1)],
      'open': const [Beat(2.6, 1), Beat(2.67, .06), Beat(2.8, 1, Easings.out)],
      'yaw': const [Beat(2.0, 0), Beat(2.25, -.5), Beat(2.45, -.5), Beat(2.75, .5), Beat(2.9, .5), Beat(3.05, 0)],
      'pitch': const [Beat(1.9, .2), Beat(3.0, .2), Beat(3.2, 0)],
      // His hands on the edge of the island, just above its bottom, then
      // hanging once he is up; the right one waves.
      'arms': const [Beat(2.95, 0), Beat(3.12, 1, Easings.back), Beat(5.45, 1), Beat(5.7, 0, Easings.inOut)],
      'handLeftX': const [Beat(2.95, .3), Beat(3.4, .3), Beat(3.75, 0, Easings.inOut)],
      'handLeftY': const [Beat(2.95, -.4), Beat(3.4, -.4), Beat(3.75, 0, Easings.inOut)],
      'handRightX': [
        const Beat(2.95, -.3),
        const Beat(3.4, -.3),
        const Beat(3.75, 0, Easings.inOut),
        const Beat(4.1, 0),
        const Beat(4.4, .23, Easings.back),
        ...Choreography.wiggle(4.4, 5.15, .23, .14, 3),
        const Beat(5.4, 0, Easings.inOut),
      ],
      'handRightY': const [Beat(2.95, -.4), Beat(3.4, -.4), Beat(3.75, 0, Easings.inOut), Beat(4.1, 0), Beat(4.4, -1.17, Easings.back), Beat(5.15, -1.17), Beat(5.4, 0, Easings.inOut)],
      'handRightTurn': [const Beat(4.4, 0), ...Choreography.wiggle(4.4, 5.15, 0, .35, 3)],
      'tilt': const [Beat(4.1, 0), Beat(4.4, -.12), Beat(5.15, -.12), Beat(5.4, 0)],
      'happy': const [Beat(4.1, 0), Beat(4.11, 1, Easings.linear), Beat(5.2, 1), Beat(5.21, 0, Easings.linear)],
    },
  );
}

/// His arms on their own (2026-10-06, « des bras plutôt » than paws):
/// one loop that goes through what they could do, played by each
/// [ArmStyle].
abstract final class ArmLoops {
  /// Out of his body, hello, the task beside him, hooray, back in.
  static final tour = Choreography(
    name: 'Les bras',
    duration: 6.2,
    marks: const [Mark(.1, 'sortent'), Mark(.7, 'coucou'), Mark(2.3, 'montre'), Mark(3.6, 'youpi'), Mark(5.5, 'rentrent')],
    tracks: {
      'arms': const [Beat(.1, 0), Beat(.5, 1, Easings.back), Beat(5.5, 1), Beat(5.9, 0, Easings.inOut)],
      // Hello: the right hand up beside his head, waving.
      'handRightX': [
        const Beat(.7, 0),
        const Beat(1.0, .23, Easings.back),
        ...Choreography.wiggle(1.0, 2.0, .23, .14, 3),
        const Beat(2.2, 0, Easings.inOut),
        // The task, on his right.
        const Beat(2.55, .62, Easings.back),
        const Beat(3.3, .62),
        const Beat(3.55, 0, Easings.inOut),
        // Hooray.
        const Beat(3.8, .05, Easings.back),
        const Beat(4.9, .05),
        const Beat(5.2, 0, Easings.inOut),
      ],
      'handRightY': const [
        Beat(.7, 0),
        Beat(1.0, -1.17, Easings.back),
        Beat(2.0, -1.17),
        Beat(2.2, 0, Easings.inOut),
        Beat(2.55, -.55, Easings.back),
        Beat(3.3, -.55),
        Beat(3.55, 0, Easings.inOut),
        Beat(3.8, -1.6, Easings.back),
        Beat(4.9, -1.6),
        Beat(5.2, 0, Easings.inOut),
      ],
      'handRightTurn': [const Beat(1.0, 0), ...Choreography.wiggle(1.0, 2.0, 0, .35, 3)],
      'handLeftX': const [Beat(3.55, 0), Beat(3.8, -.05, Easings.back), Beat(4.9, -.05), Beat(5.2, 0, Easings.inOut)],
      'handLeftY': [const Beat(3.55, 0), const Beat(3.8, -1.6, Easings.back), ...Choreography.wiggle(3.8, 4.9, -1.6, .08, 3), const Beat(5.2, 0, Easings.inOut)],
      'yaw': const [Beat(2.2, 0), Beat(2.45, .5), Beat(3.3, .5), Beat(3.55, 0)],
      'tilt': const [Beat(.8, 0), Beat(1.0, -.1), Beat(2.0, -.1), Beat(2.2, 0)],
      'y': const [Beat(3.6, 0), Beat(3.75, -.18, Easings.out), Beat(3.95, 0, Easings.inCubic), Beat(4.2, 0), Beat(4.35, -.12, Easings.out), Beat(4.55, 0, Easings.inCubic)],
      'happy': const [Beat(.9, 0), Beat(.91, 1, Easings.linear), Beat(2.0, 1), Beat(2.01, 0, Easings.linear), Beat(3.6, 0), Beat(3.61, 1, Easings.linear), Beat(4.95, 1), Beat(4.96, 0, Easings.linear)],
    },
  );

  /// Instants of [tour] to compare the styles still: at rest, hello, the
  /// task, hooray.
  static const stills = [('Au repos', .6), ('Coucou', 1.5), ('Montre', 2.9), ('Youpi', 4.4)];

  static const notes = {
    ArmStyle.noodle: 'Souples, pliés comme un tuyau, une main ronde (les dessins animés des années 30).',
    ArmStyle.stick: 'Des traits fins et une petite main ronde : un personnage d’autocollant, très épuré.',
    ArmStyle.nub: 'Courts, épais et ronds : des bosses de son corps, comme ses oreilles.',
    ArmStyle.fluffy: 'Poilus comme lui, une touffe au bout.',
    ArmStyle.mitten: 'Souples, avec des moufles et un pouce.',
  };

  static const names = {
    ArmStyle.noodle: 'Bras souples',
    ArmStyle.stick: 'Bras fins',
    ArmStyle.nub: 'Moignons',
    ArmStyle.fluffy: 'Bras poilus',
    ArmStyle.mitten: 'Moufles',
  };
}

/// Mikky's pose at [t] in [c].
MikkyPose poseAt(Choreography c, double t) {
  final pose = MikkyPose();
  for (final prop in MikkyProp.values) {
    if (c.tracks.containsKey(prop.name)) pose[prop] = c.value(prop.name, t);
  }
  return pose;
}

/// Mikky as [c] has him at [t], with radius [r].
MikkyGeometry geometryAt(Choreography c, double t, double r, {ArmStyle arms = ArmStyle.noodle}) {
  final furball = c.value('furball', t);
  final eyes = c.value('happy', t) > .5
      ? EyeShape.happy
      : c.value('closed', t) > .5
          ? EyeShape.closed
          : EyeShape.oval;
  return MikkyGeometry.posed(
    poseAt(c, t),
    r,
    time: t,
    eyeLeft: eyes,
    eyeRight: eyes,
    form: furball.abs() > .001 ? MikkyForm.furball : MikkyForm.cat,
    morph: furball,
    arms: arms,
  );
}

/// The island's shader, loaded once.
final Future<ui.FragmentProgram?> _program = loadIslandProgram();

/// The top of a screen at the instant [t] of a launch: the island glued
/// to its top edge, Mikky in it, the particles.
class LaunchScene extends StatelessWidget {
  const LaunchScene(this.choreography, this.t, {super.key, this.size = const Size(520, 190), this.arms = ArmStyle.noodle});

  final Choreography choreography;
  final double t;
  final Size size;
  final ArmStyle arms;

  @override
  Widget build(BuildContext context) {
    final mui = MikkyUi.of(context);
    return FutureBuilder<ui.FragmentProgram?>(
      future: _program,
      builder: (context, shot) => CustomPaint(
        size: size,
        painter: _LaunchPainter(
          choreography,
          t,
          shot.data?.fragmentShader(),
          mui.isLight ? MikkyTheme.light : MikkyTheme.dark,
          mui,
          MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
          arms,
        ),
      ),
    );
  }
}

class _LaunchPainter extends CustomPainter {
  _LaunchPainter(this.c, this.t, this.shader, this.theme, this.mui, this.dpr, this.arms);

  final Choreography c;
  final double t;
  final ui.FragmentShader? shader;
  final MikkyTheme theme;
  final MikkyUi mui;
  final double dpr;
  final ArmStyle arms;

  static final _ring = Burst(
    seed: 11,
    count: 44,
    speedMin: 70,
    speedMax: 160,
    sizeMin: .9,
    sizeMax: 2.1,
    lifeMin: .45,
    lifeMax: .8,
    drag: 3.2,
    alphaMin: .4,
  );
  static final _pop = Burst(seed: 5, count: 36, speedMin: 90, speedMax: 210, sizeMin: 1, sizeMax: 2.4, lifeMin: .4, lifeMax: .75, drag: 3.6);
  static final _dust = Burst(
    seed: 9,
    count: 14,
    angleFrom: math.pi * 1.05,
    angleTo: math.pi * 1.95,
    speedMin: 40,
    speedMax: 95,
    sizeMin: 1.5,
    sizeMax: 2.5,
    lifeMin: .35,
    lifeMax: .6,
    gravity: 260,
  );

  /// The streaks of the fall (« La chute »): x across the island (0 to 1),
  /// start, speed, length, brightness.
  static final _streaks = () {
    final rng = math.Random(7);
    return [
      for (var i = 0; i < 34; i++)
        (x: .08 + .84 * rng.nextDouble(), t0: .22 + .3 * rng.nextDouble(), v: 520 + 260 * rng.nextDouble(), len: 8 + 16 * rng.nextDouble(), a: .2 + .45 * rng.nextDouble()),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final light = mui.isLight;
    // The top of a screen: a soft wallpaper.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), light
            ? const [Color(0xFFDDE3EC), Color(0xFFC8D1DE)]
            : const [Color(0xFF2A2C35), Color(0xFF17181D)]),
    );
    final cx = size.width / 2;
    final iw = c.value('iw', t), ih = c.value('ih', t);
    if (ih < .5) return;
    final r = math.min(ih / 2, 30.0);
    final visible = Rect.fromLTWH(cx - iw / 2, 0, iw, ih);
    IslandPainter(
      shader: shader,
      shape: Rect.fromLTRB(visible.left, -40, visible.right, visible.bottom),
      visible: visible,
      radius: r,
      visibility: 1,
      theme: theme,
      devicePixelRatio: dpr,
      corners: 2,
    ).paint(canvas, size);

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndCorners(visible, bottomLeft: Radius.circular(r), bottomRight: Radius.circular(r)));
    final ink = light ? const Color(0xFF0C0C0E) : const Color(0xFFFFFFFF);
    final paint = Paint();

    // The fall: streaks going down.
    if (c.name == Launches.fall.name) {
      for (final s in _streaks) {
        final age = t - s.t0;
        if (age < 0 || age > .55) continue;
        final y = age * s.v - 10, x = visible.left + s.x * iw;
        final fade = (1 - age / .55);
        paint
          ..color = ink.withValues(alpha: s.a * fade)
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x, y - s.len), Offset(x, y), paint);
      }
    }

    // Dust where he lands, sparks where he hatches.
    void ring(Burst b, String mark, Offset at, {double flat = 1, bool squares = false}) {
      final m = c.at(mark);
      if (m == null || t < m) return;
      for (final s in b.at(t - m)) {
        paint.color = ink.withValues(alpha: s.alpha * (light ? .55 : .8));
        final o = at + Offset(s.x, s.y * flat);
        if (squares) {
          canvas.drawRect(Rect.fromCenter(center: Offset(o.dx.roundToDouble(), o.dy.roundToDouble()), width: s.size, height: s.size), paint);
        } else {
          canvas.drawCircle(o, s.size / 2, paint);
        }
      }
    }

    final mx = cx + c.value('x', t), my = c.value('y', t);
    final feet = Offset(mx, my + Launches.radius * .8);
    // The dust of his landing, behind him: only what flies out on the
    // sides shows.
    if (c.name == Launches.arms.name) ring(_dust, 'atterrit', feet, squares: true);

    // Mikky.
    final g = geometryAt(c, t, Launches.radius, arms: arms);
    MikkyPainter(
      geometry: g,
      center: Offset(mx, my),
      rim: theme.mikkyRim,
      statusColor: theme.status,
      foreground: theme.foreground,
      showBadge: false,
    ).paint(canvas, size);

    if (c.name == Launches.fall.name) ring(_ring, 'atterrit', feet, flat: .32);
    if (c.name == Launches.hatch.name) {
      ring(_pop, 'éclot', Offset(mx, my));
      final m = c.at('éclot')!;
      // Three small pixel fireworks around him, ours.
      for (final (i, (dx, dy)) in const [(-1.9, -.5), (1.9, -.7), (0.0, -1.6)].indexed) {
        final age = t - m - i * .08;
        if (age < 0 || age > .7) continue;
        final frame = age < .18 ? 0 : (age < .38 ? 1 : 2);
        final fade = age > .45 ? 1 - (age - .45) / .25 : 1.0;
        final palette = [PixelFxPalette.blue, PixelFxPalette.violet, PixelFxPalette.fire][i].on(mui);
        const px = 2.5;
        for (var y = -3; y <= 3; y++) {
          for (var x = -3; x <= 3; x++) {
            final level = pixelLevel(CalmFirework.frame(frame, x, y));
            if (level == null) continue;
            paint.color = palette.levels[level].withValues(alpha: fade);
            canvas.drawRect(Rect.fromLTWH(mx + dx * Launches.radius + x * px, my + dy * Launches.radius + y * px, px, px), paint);
          }
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LaunchPainter old) => old.t != t || old.c != c || old.shader != shader || old.theme != theme || old.arms != arms;
}

/// Mikky alone at the instant [t] of a loop of his (the arms).
class PoseScene extends StatelessWidget {
  const PoseScene(this.choreography, this.t, {super.key, this.size = const Size(240, 150), this.arms = ArmStyle.noodle, this.radius = 34});

  final Choreography choreography;
  final double t;
  final Size size;
  final ArmStyle arms;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final mui = MikkyUi.of(context);
    final theme = mui.isLight ? MikkyTheme.light : MikkyTheme.dark;
    return Container(
      width: size.width,
      height: size.height,
      color: mui.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708),
      child: CustomPaint(
        painter: _PosePainter(choreography, t, theme, arms, radius),
      ),
    );
  }
}

class _PosePainter extends CustomPainter {
  _PosePainter(this.c, this.t, this.theme, this.arms, this.radius);

  final Choreography c;
  final double t;
  final MikkyTheme theme;
  final ArmStyle arms;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    MikkyPainter(
      geometry: geometryAt(c, t, radius, arms: arms),
      // `y` moves him (units of his radius): his hops.
      center: Offset(size.width / 2, size.height * .58 + c.value('y', t) * radius),
      rim: theme.mikkyRim,
      statusColor: theme.status,
      foreground: theme.foreground,
      showBadge: false,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(_PosePainter old) => old.t != t || old.c != c || old.theme != theme || old.arms != arms || old.radius != radius;
}
