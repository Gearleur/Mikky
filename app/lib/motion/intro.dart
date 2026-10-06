import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import '../ui/pixel_fx.dart';
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
  static final all = [pop];

  /// Pops up from his shadow: the shadow first, then him, overshooting a
  /// little and settling, eyes shut, then open; ears flop late. Then his
  /// magic, ultra fast (2026-10-06, « ses pouvoirs magiques, orange, mais
  /// vraiment ultra rapide, avec une petite étoile qui explose sur le
  /// côté »): he flashes orange, a little star bursts beside him. A curious
  /// tilt, and a small happy hop.
  static final pop = Choreography(
    name: 'Le pop',
    duration: 3.35,
    marks: const [Mark(0, 'l’ombre'), Mark(.32, 'pop'), Mark(.9, 'ouvre les yeux'), Mark(1.25, 'pouvoir'), Mark(1.41, 'éclate'), Mark(1.75, 'curieux'), Mark(2.55, 'content')],
    tracks: {
      'shadow': const [Beat(0, 0), Beat(.32, 1, Easings.out)],
      'size': [const Beat(.3, 0), Beat(.85, 1, Easings.spring(const SpringSpec(240, .42), .55))],
      'h': const [Beat(.3, 0), Beat(.52, .45, Easings.out), Beat(.72, 0, Easings.inCubic), Beat(2.55, 0), Beat(2.73, .35, Easings.out), Beat(2.91, 0, Easings.inCubic)],
      'scaleY': [
        const Beat(.3, 1.2),
        const Beat(.72, 1.12),
        const Beat(.78, .8, Easings.out),
        Beat(1.1, 1, Easings.spring(const SpringSpec(260, .4), .32)),
        const Beat(1.25, 1),
        const Beat(1.29, 1.1, Easings.out),
        Beat(1.5, 1, Easings.spring(const SpringSpec(300, .4), .21)),
        const Beat(2.49, 1),
        const Beat(2.55, .88, Easings.out),
        const Beat(2.73, 1.06),
        const Beat(2.95, .9, Easings.out),
        Beat(3.2, 1, Easings.spring(const SpringSpec(260, .45), .25)),
      ],
      'scaleX': [
        const Beat(.3, .85),
        const Beat(.72, .9),
        const Beat(.78, 1.18, Easings.out),
        Beat(1.1, 1, Easings.spring(const SpringSpec(260, .4), .32)),
        const Beat(1.25, 1),
        const Beat(1.29, .93, Easings.out),
        Beat(1.5, 1, Easings.spring(const SpringSpec(300, .4), .21)),
        const Beat(2.49, 1),
        const Beat(2.55, 1.1, Easings.out),
        const Beat(2.73, .95),
        const Beat(2.95, 1.1, Easings.out),
        Beat(3.2, 1, Easings.spring(const SpringSpec(260, .45), .25)),
      ],
      'open': const [Beat(.3, .08), Beat(.88, .08), Beat(1.0, 1, Easings.out)],
      'eyeScale': const [Beat(.9, 1), Beat(1.05, 1.15, Easings.back), Beat(1.2, 1), Beat(1.29, 1.22, Easings.out), Beat(1.6, 1, Easings.inOut)],
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
      'tilt': const [Beat(1.75, 0), Beat(2.0, .2, Easings.inOut), Beat(2.3, .2), Beat(2.5, 0, Easings.inOut)],
      'yaw': const [Beat(1.25, 0), Beat(1.32, .35, Easings.out), Beat(1.55, .35), Beat(1.75, 0, Easings.inOut), Beat(2.0, .3, Easings.inOut), Beat(2.3, .3), Beat(2.5, 0, Easings.inOut)],
      'happy': const [Beat(2.55, 0), Beat(2.56, 1, Easings.linear)],
    },
  );

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
    // His magic: a glow behind him, his fur orange for an instant.
    final power = c.value('power', t);
    // The little star beside him, and its burst of pixel sparks.
    final star = c.value('star', t);
    final starAt = here + Offset(r * 1.85, -r * 1.05);
    if (star > .01) {
      canvas.drawCircle(starAt, r * .9 * star, Paint()
        ..color = _orange.withValues(alpha: .45 * math.min(1, star))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .35));
      canvas.drawPath(_sparkle(starAt, r * .7 * star), Paint()..color = _orange.withValues(alpha: math.min(1, star * 1.3)));
      canvas.drawPath(_sparkle(starAt, r * .34 * star), Paint()..color = const Color(0xFFFFF4B8));
    }
    final burst = c.at('éclate');
    if (burst != null && t >= burst) {
      final age = t - burst;
      // A ring that opens and fades.
      if (age < .35) {
        final q = age / .35;
        canvas.drawCircle(starAt, r * (.3 + 1.4 * Easings.out(q)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * .12 * (1 - q)
          ..color = _orange.withValues(alpha: (1 - q) * .9));
      }
      final paint = Paint()..isAntiAlias = false;
      final px = (r * .1).roundToDouble().clamp(2.0, 6.0);
      for (final s in _burst.at(age)) {
        final o = starAt + Offset(s.x, s.y);
        paint.color = PixelFxPalette.signatureOrange.levels[(s.progress * 4).floor().clamp(0, 3)].withValues(alpha: s.alpha);
        final big = s.size > 3.6 ? px * 1.5 : px;
        canvas.drawRect(Rect.fromLTWH((o.dx / px).roundToDouble() * px, (o.dy / px).roundToDouble() * px, big, big), paint);
      }
    }
    MikkyPainter(
      geometry: geometryAt(c, t, r * grow),
      center: Offset(x, y),
      statusColor: MikkyTheme.light.status,
      foreground: MikkyTheme.light.foreground,
      showBadge: false,
      fur: power > 0 ? Color.lerp(MikkyPainter.ink, _orange, power) : null,
      glow: power > 0 ? _orange.withValues(alpha: .95 * power) : null,
    ).paint(canvas, size);
  }

  static const _orange = Color(0xFFFF8204);
  static final _burst = Burst(seed: 31, count: 44, speedMin: 120, speedMax: 280, sizeMin: 2, sizeMax: 4.5, lifeMin: .4, lifeMax: .75, drag: 3, alphaMin: .85);

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
        ..color = Color.fromRGBO(0, 0, 0, .2 * (1 - .6 * far) * amount)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .12),
    );
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.t != t || old.c != c || old.radius != radius;
}
