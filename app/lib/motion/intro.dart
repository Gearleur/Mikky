import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import '../ui/pixel_fx.dart';
import 'launch.dart';
import 'sprite128.dart';

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
  static final all = [pop];

  /// Pops up from his shadow: the shadow first, then him, overshooting a
  /// little and settling, eyes shut, then open; ears flop late. Then his
  /// magic, ultra fast (2026-10-06, « ses pouvoirs magiques, orange, mais
  /// vraiment ultra rapide, avec une petite étoile qui explose sur le
  /// côté »): he flashes orange, a little star bursts beside him. Then a
  /// small happy hop (no curious tilt: « enlève-le »).
  // A little slower (2026-10-06, « ralentis ×0,8 »).
  static final pop = Choreography(
    name: 'Le pop',
    duration: 2.6,
    marks: const [
      Mark(0, 'l’ombre'),
      Mark(.32, 'pop'),
      Mark(.9, 'ouvre les yeux'),
      Mark(1.25, 'pouvoir'),
      Mark(1.41, 'éclate'),
      Mark(1.8, 'content'),
    ],
    tracks: {
      'shadow': const [Beat(0, 0), Beat(.32, 1, Easings.out)],
      'size': [const Beat(.3, 0), Beat(.85, 1, Easings.spring(const SpringSpec(240, .42), .55))],
      'h': const [
        Beat(.3, 0),
        Beat(.52, .45, Easings.out),
        Beat(.72, 0, Easings.inCubic),
        Beat(1.8, 0),
        Beat(1.98, .35, Easings.out),
        Beat(2.16, 0, Easings.inCubic),
      ],
      'scaleY': [
        const Beat(.3, 1.2),
        const Beat(.72, 1.12),
        const Beat(.78, .8, Easings.out),
        Beat(1.1, 1, Easings.spring(const SpringSpec(260, .4), .32)),
        const Beat(1.25, 1),
        const Beat(1.29, 1.1, Easings.out),
        Beat(1.5, 1, Easings.spring(const SpringSpec(300, .4), .21)),
        const Beat(1.74, 1),
        const Beat(1.8, .88, Easings.out),
        const Beat(1.98, 1.06),
        const Beat(2.2, .9, Easings.out),
        Beat(2.45, 1, Easings.spring(const SpringSpec(260, .45), .25)),
      ],
      'scaleX': [
        const Beat(.3, .85),
        const Beat(.72, .9),
        const Beat(.78, 1.18, Easings.out),
        Beat(1.1, 1, Easings.spring(const SpringSpec(260, .4), .32)),
        const Beat(1.25, 1),
        const Beat(1.29, .93, Easings.out),
        Beat(1.5, 1, Easings.spring(const SpringSpec(300, .4), .21)),
        const Beat(1.74, 1),
        const Beat(1.8, 1.1, Easings.out),
        const Beat(1.98, .95),
        const Beat(2.2, 1.1, Easings.out),
        Beat(2.45, 1, Easings.spring(const SpringSpec(260, .45), .25)),
      ],
      'open': const [Beat(.3, .08), Beat(.88, .08), Beat(1, 1, Easings.out)],
      'eyeScale': const [
        Beat(.9, 1),
        Beat(1.05, 1.15, Easings.back),
        Beat(1.2, 1),
        Beat(1.29, 1.22, Easings.out),
        Beat(1.6, 1),
      ],
      'earLeft': [
        const Beat(.3, -.6),
        const Beat(.8, -.6),
        Beat(1.2, 0, Easings.spring(const SpringSpec(180, .35), .4)),
        const Beat(1.25, 0),
        const Beat(1.29, .55, Easings.out),
        Beat(1.6, 0, Easings.spring(const SpringSpec(200, .4), .31)),
      ],
      'earRight': [
        const Beat(.3, -.6),
        const Beat(.86, -.6),
        Beat(1.22, 0, Easings.spring(const SpringSpec(180, .35), .36)),
        const Beat(1.27, 0),
        const Beat(1.31, .55, Easings.out),
        Beat(1.62, 0, Easings.spring(const SpringSpec(200, .4), .31)),
      ],
      // His magic: orange in a flash, ultra fast.
      'power': const [Beat(1.25, 0), Beat(1.29, 1, Easings.out), Beat(1.4, 1), Beat(1.62, 0, Easings.out)],
      'star': const [Beat(1.2, 0), Beat(1.3, 1, Easings.back), Beat(1.38, 1.15), Beat(1.42, 0, Easings.inCubic)],
      // A little shake as the magic goes out of him.
      'offsetX': [const Beat(1.27, 0), ...Choreography.wiggle(1.27, 1.45, 0, .05, 3)],
      'yaw': const [Beat(1.25, 0), Beat(1.32, .35, Easings.out), Beat(1.55, .35), Beat(1.75, 0)],
      'happy': const [Beat(1.8, 0), Beat(1.81, 1, Easings.linear)],
    },
  ).atSpeed(.8);
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
  Widget build(BuildContext context) => CustomPaint(size: size, painter: IntroPainter(choreography, t, radius));
}

/// An intro at [t]; on its white stage, or on the island ([stage]
/// false: the island is the background, [theme] its own).
class IntroPainter extends CustomPainter {
  IntroPainter(this.c, this.t, this.radius, {this.stage = true, this.theme = MikkyTheme.light});

  final Choreography c;
  final double t;
  final double radius;
  final bool stage;
  final MikkyTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    // White, a touch warm at the bottom, like a lit floor.
    if (stage) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFF6F6F4)],
          ).createShader(Offset.zero & size),
      );
    }
    final r = radius;
    final ground = size.height * .8;
    // Where he is at [at]: his bottom on the ground (or `h` above it),
    // however squashed.
    Offset place(double at) {
      final grow = c.value('size', at, 1);
      final x = size.width / 2 + c.value('x', at) * r;
      return Offset(x, ground - MikkyShape.halfHeight * r * c.value('scaleY', at, 1) * grow - c.value('h', at) * r);
    }

    final grow = c.value('size', t, 1);
    final h = c.value('h', t);
    final here = place(t);
    if (grow <= .01) {
      _shadow(canvas, size, Offset(here.dx, ground), h, 1, c.value('shadow', t, 1));
      return;
    }
    final x = here.dx, y = here.dy;
    _shadow(canvas, size, Offset(x, ground), h, grow, c.value('shadow', t, 1));
    // His magic (« dès que Mikky change de couleur, il doit être en 128
    // bits »): in color, he and all his effects are 128-bit sprites.
    final power = c.value('power', t);
    final star = c.value('star', t);
    final starAt = here + Offset(r * 1.85, -r * 1.05);
    final g = geometryAt(c, t, r * grow);
    MikkyPainter(
      geometry: g,
      center: Offset(x, y),
      rim: theme.mikkyRim,
      statusColor: theme.status,
      foreground: theme.foreground,
      showBadge: false,
    ).paint(canvas, size);
    if (power > .01) {
      final (body, eyes) = _bodyAndEyes(g, Offset(x, y));
      drawSprite128(
        canvas,
        body,
        palette: _palette,
        light: Offset(x, y - r * grow * .25),
        reach: r * grow * 1.3,
        holes: eyes,
        halo: 9,
        fade: power,
      );
    }
    // The star beside him, then its burst: a ring that opens, sparks.
    if (star > .01) {
      drawSprite128(
        canvas,
        _sparkle(starAt, r * .7 * star),
        palette: _palette,
        light: starAt,
        reach: r * .55 * star,
        halo: 5,
      );
    }
    final burst = c.at('éclate');
    if (burst != null && t >= burst) {
      final age = t - burst;
      if (age < .35) {
        final q = age / .35;
        final out = r * (.3 + 1.4 * Easings.out(q)), width = math.max(1.5, r * .14 * (1 - q));
        final ring = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: starAt, radius: out)),
          Path()..addOval(Rect.fromCircle(center: starAt, radius: out - width)),
        );
        drawSprite128(canvas, ring, palette: _palette, light: starAt, reach: out, halo: 2, fade: 1 - q);
      }
      final paint = Paint()..isAntiAlias = false;
      final px = (r * .1).roundToDouble().clamp(2.0, 6.0);
      for (final s in _burst.at(age)) {
        final o = starAt + Offset(s.x, s.y);
        paint.color = _palette.levels[(s.progress * 4).floor().clamp(0, 3)].withValues(alpha: s.alpha);
        final big = s.size > 3.6 ? px * 1.5 : px;
        canvas.drawRect(
          Rect.fromLTWH((o.dx / px).roundToDouble() * px, (o.dy / px).roundToDouble() * px, big, big),
          paint,
        );
      }
    }
  }

  /// His body and his eyes where they are drawn, for the sprites.
  static (Path, List<Path>) _bodyAndEyes(MikkyGeometry g, Offset center) {
    final m = Matrix4.identity()
      ..translateByDouble(center.dx + g.translateX, center.dy + g.translateY, 0, 1)
      ..rotateZ(g.tilt)
      ..scaleByDouble(g.scaleX, g.scaleY, 1, 1);
    final body = Path()
      ..addPolygon([for (var i = 0; i < g.pointCount; i++) Offset(g.contour[i * 2], g.contour[i * 2 + 1])], true);
    final eyes = [
      for (final e in g.eyes)
        (Path()..addOval(Rect.fromCenter(center: Offset.zero, width: e.width, height: e.height))).transform(
          (Matrix4.copy(m)
                ..translateByDouble(e.x, e.y, 0, 1)
                ..rotateZ(e.rotation)
                ..scaleByDouble(e.scaleX, e.scaleY, 1, 1))
              .storage,
        ),
    ];
    return (body.transform(m.storage), eyes);
  }

  /// Our signature orange.
  static const _palette = PixelFxPalette.signatureOrange;

  static final _burst = Burst(
    seed: 31,
    count: 44,
    speedMin: 120,
    speedMax: 280,
    sizeMin: 2,
    sizeMax: 4.5,
    lifeMin: .4,
    lifeMax: .75,
    drag: 3,
    alphaMin: .85,
  );

  /// A four-pointed sparkle at [c], [o] from its middle to a point.
  static Path _sparkle(Offset c, double o) {
    final i = o * .2;
    return Path()
      ..moveTo(c.dx, c.dy - o)
      ..quadraticBezierTo(c.dx + i, c.dy - i, c.dx + o, c.dy)
      ..quadraticBezierTo(c.dx + i, c.dy + i, c.dx, c.dy + o)
      ..quadraticBezierTo(c.dx - i, c.dy + i, c.dx - o, c.dy)
      ..quadraticBezierTo(c.dx - i, c.dy - i, c.dx, c.dy - o)
      ..close();
  }

  /// His shadow: smaller and paler the higher he is.
  void _shadow(Canvas canvas, Size size, Offset at, double h, double grow, double amount) {
    if (amount <= 0) return;
    final far = math.min(h / 5, 1.0);
    final w = radius * 2.1 * grow.clamp(.35, 1.0) * (1 - .55 * far) * amount;
    canvas.drawOval(
      Rect.fromCenter(center: at + const Offset(0, 2), width: w, height: w * .2),
      Paint()
        // On the dark island, a faint light under him instead.
        ..color = (theme.isLight ? const Color(0xFF000000) : const Color(0xFFFFFFFF)).withValues(
          alpha: (theme.isLight ? .2 : .07) * (1 - .6 * far) * amount,
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .12),
    );
  }

  @override
  bool shouldRepaint(IntroPainter old) =>
      old.t != t || old.c != c || old.radius != radius || old.stage != stage || old.theme != theme;
}
