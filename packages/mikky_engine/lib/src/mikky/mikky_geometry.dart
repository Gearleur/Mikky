import 'dart:math' as math;
import 'dart:typed_data';

import 'mikky.dart';
import 'mikky_tuning.dart';

/// Mikky's fixed silhouette ("G" + tufts, spec §3), in units of the radius
/// R. The adjustable part is in [MikkyTuning].
abstract final class MikkyShape {
  /// Superellipse exponent.
  static const exponent = 2.4;
  static const halfWidth = 1.06;
  static const halfHeight = .92;

  /// Ears: bumps of the same outline.
  static const earOuterHalfWidth = .40; // × half width
  static const earInnerHalfWidth = .44; // × half width
  static const earCurve = .85;

  /// Eyes: ovals on a sphere, no pupil.
  static const eyeWidth = .21; // × R
  static const eyeBaseHeight = .50; // × R, × elongation
}

/// One eye, in the body's local frame (before the body transform).
class EyeGeometry {
  const EyeGeometry({
    required this.x,
    required this.y,
    required this.rotation,
    required this.scaleX,
    required this.scaleY,
    required this.width,
    required this.height,
    required this.fullHeight,
    required this.shape,
    required this.side,
  });

  /// Center.
  final double x, y;

  /// Apply in this order: translate(x, y), rotate, scale.
  final double rotation, scaleX, scaleY;

  /// Size of the oval before scaling; [height] includes the eyelid,
  /// [fullHeight] is the eye wide open.
  final double width, height, fullHeight;
  final EyeShape shape;

  /// -1 left, 1 right.
  final double side;
}

/// Everything needed to draw Mikky at one instant, in pixels.
///
/// To draw: translate([translateX], [translateY]) from Mikky's anchor,
/// rotate([tilt]), scale([scaleX], [scaleY]); fill [contour]; clip to it and
/// draw [eyes]. [badge] and [particles] are drawn from the anchor, without
/// the body transform.
class MikkyGeometry {
  MikkyGeometry._({
    required this.radius,
    required this.time,
    required this.contour,
    required this.satellites,
    required this.eyes,
    required this.translateX,
    required this.translateY,
    required this.tilt,
    required this.scaleX,
    required this.scaleY,
    required this.badge,
    required this.badgeX,
    required this.badgeY,
    required this.particles,
  });

  final double radius;

  /// Mikky's clock, for the shapes that move by themselves (spiral, dots).
  final double time;

  /// Closed outline: x0, y0, x1, y1, ... (y down), centered on Mikky.
  final Float64List contour;

  /// Other bits of him (the fur balls of "•••" and "!"), same format and
  /// same transform as [contour]. Eyes are only on [contour].
  final List<Float64List> satellites;
  final List<EyeGeometry> eyes;
  final double translateX, translateY, tilt, scaleX, scaleY;

  final MikkyBadge? badge;

  /// Badge center, in pixels from the anchor.
  final double badgeX, badgeY;

  /// Positions and sizes in pixels from the anchor.
  final List<MikkyParticle> particles;

  int get pointCount => contour.length ~/ 2;

  /// Geometry of [mikky] drawn with radius [radius] pixels, with [points]
  /// points on the outline.
  factory MikkyGeometry.of(Mikky mikky, double radius, {int points = 360, MikkyTuning? tuning}) {
    final tu = tuning ?? MikkyTuning.defaults;
    final p = mikky.pose;
    final t = mikky.time;
    final r = radius;
    final rx = r * MikkyShape.halfWidth, ry = r * MikkyShape.halfHeight;
    const ex = 2 / MikkyShape.exponent;
    final k = tu.bottomWiden;

    double earBump(double x) {
      var best = 0.0;
      for (final side in const [-1.0, 1.0]) {
        final twitch = side < 0 ? p.earLeft : p.earRight;
        // Raised ears grow and lean in a little; lowered ones go flat to the
        // side, like a cat's, instead of just shrinking.
        final down = math.max(0.0, -twitch);
        final center = side * rx * tu.earCenter + p.yaw * rx * .28 + side * twitch * rx * .06 + side * down * rx * .3;
        final d = x - center;
        final halfWidth = (d * side > 0 ? MikkyShape.earOuterHalfWidth : MikkyShape.earInnerHalfWidth) *
            rx *
            tu.earWidth *
            (1 + down * .35);
        final tri = (1 - d.abs() / halfWidth).clamp(0.0, 1.0);
        final grow = twitch > 0 ? 1 + twitch * .9 : 1 + twitch * .6;
        // The far ear gets a bit shorter when the head turns.
        final height = tu.earHeight * r * grow * (1 - .18 * (side * p.yaw).clamp(0.0, 1.0));
        best = math.max(best, math.max(0.0, height) * math.pow(tri, MikkyShape.earCurve));
      }
      return best;
    }

    // m: how far into the form (may overshoot, like jelly); w: the same,
    // kept in 0..1 for what must not overshoot (ears, tufts, eyes).
    final form = mikky.form;
    final m = form == MikkyForm.cat ? 0.0 : mikky.morph;
    final w = m.clamp(0.0, 1.0);

    final contour = Float64List((points + 1) * 2);
    for (var i = 0; i <= points; i++) {
      final th = i / points * math.pi * 2;
      final c = math.cos(th), s = math.sin(th);
      final px = c.sign * math.pow(c.abs(), ex);
      final py = s.sign * math.pow(s.abs(), ex);
      var x = rx * px * (1 + k * py);
      var y = ry * py;
      // The ears melt into the form.
      if (py < 0) y -= earBump(x) * (1 - w);
      // Tufts: one on top of the head, fluffy cheeks, slowly waving.
      final top = math.exp(-math.pow((th - math.pi * 1.5) / .16, 2));
      final cheeks = math.exp(-math.pow((th - .18) / .22, 2)) + math.exp(-math.pow((th - (math.pi - .18)) / .22, 2));
      final fluff = 1 + (top * .09 + cheeks * .05) * math.sin(th * 40 + math.sin(t * 2.5) * .5).abs() * (1 - w);
      x *= fluff;
      y *= fluff;
      if (m != 0) {
        final (fx, fy) = _formPoint(form, th, t);
        x += (fx * r - x) * m;
        y += (fy * r - y) * m;
      }
      contour[i * 2] = x;
      contour[i * 2 + 1] = y;
    }

    final eyes = <EyeGeometry>[];
    final anchor = _eyeAnchor(form);
    for (final side in const [-1.0, 1.0]) {
      final yaw = side * tu.eyeSpread + p.yaw;
      final pitch = tu.eyeElevation + p.pitch;
      final cp = math.cos(pitch);
      // Eye turned away from the viewer: hidden behind the head (on the cat;
      // on a form, both eyes stay).
      if (math.cos(yaw) * cp < .05 && w < .5) continue;
      final width = r * MikkyShape.eyeWidth * tu.eyeSize;
      final fullHeight = r * MikkyShape.eyeBaseHeight * tu.eyeElongation * tu.eyeSize;
      final shape = side < 0 ? mikky.eyeLeft : mikky.eyeRight;
      // Eyelids only close ovals; the other shapes keep their look.
      final lid = shape == EyeShape.oval || shape == EyeShape.tired ? p.open : 1.0;
      final catX = math.sin(yaw) * cp * rx * (1 - k * math.sin(pitch));
      final catY = -math.sin(pitch) * ry;
      final (ax, ay, scale) = anchor;
      final formX = (side * ax + p.yaw * .25) * r;
      final formY = (ay - p.pitch * .2) * r + _formOffsetY(form, t) * r;
      final sx = math.max(.2, math.cos(yaw)) * p.eyeScale;
      final sy = math.max(.2, cp) * p.eyeScale;
      eyes.add(EyeGeometry(
        x: catX + (formX - catX) * w,
        y: catY + (formY - catY) * w,
        rotation: (-.04 - p.yaw * .25) * (1 - w),
        scaleX: (sx + (p.eyeScale - sx) * w) * (1 + (scale - 1) * w),
        scaleY: (sy + (p.eyeScale - sy) * w) * (1 + (scale - 1) * w),
        width: width,
        height: math.max(width * .25, fullHeight * lid),
        fullHeight: fullHeight,
        shape: shape,
        side: side,
      ));
    }

    // The little fur balls that come out of him (the other two dots, the
    // dot of "!").
    final satellites = <Float64List>[
      for (final (cx, cy, cr) in _satellites(form, t))
        // Enough points for the fine fur (34 waves), or it turns into lumps.
        _furBall(cx * r * _easeOut(w), cy * r * _easeOut(w), cr * r * w, t + cx * 3, 200),
    ];

    return MikkyGeometry._(
      radius: r,
      time: t,
      contour: contour,
      satellites: satellites,
      eyes: eyes,
      translateX: p.offsetX * r + _formOffsetX(form, t) * r * w,
      translateY: p.offsetY * r,
      tilt: p.tilt,
      scaleX: p.scaleX,
      scaleY: p.scaleY,
      badge: mikky.badge,
      badgeX: r * 1.12 + p.offsetX * r,
      badgeY: -r * .95 + p.offsetY * r,
      particles: [
        for (final q in mikky.particles) MikkyParticle(q.kind, q.x * r, q.y * r, q.size * r, q.alpha, q.rotation),
      ],
    );
  }
}

// ------------------------------------------------------------------ forms
//
// Everything below is in units of R, centered on Mikky, y down. The forms
// are never perfect: their outline wobbles slowly and keeps fur.

double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();

/// Hops of the body in a form.
double _formOffsetY(MikkyForm f, double t) => switch (f) {
      MikkyForm.dots => -math.sin(t * 5.5).abs() * .22,
      MikkyForm.bang => math.sin(t * 2.2) * .03,
      _ => 0,
    };

/// The fur ball shakes itself now and then.
double _formOffsetX(MikkyForm f, double t) {
  if (f != MikkyForm.furball) return 0;
  final burst = math.pow(math.max(0.0, math.sin(t * 1.9)), 3);
  return math.sin(t * 42) * .05 * burst;
}

/// Fur all around an outline: fine, uneven, moving.
double _fur(double th, double t, double amount) =>
    amount * math.sin(th * 34 + math.sin(t * 3 + th * 5) * .6).abs() + amount * .3 * math.sin(th * 13 - t * 4);

/// Point of the form's outline for the angle [th] of the cat's outline:
/// same parameter, so the change does not twist.
(double, double) _formPoint(MikkyForm f, double th, double t) {
  double x, y, cy = 0, fur;
  switch (f) {
    case MikkyForm.cat:
      return (0, 0);
    case MikkyForm.furball:
      x = math.cos(th) * .98;
      y = math.sin(th) * .98;
      // It bristles in waves: long spikes, then smoother.
      final bristle = math.pow(math.max(0.0, math.sin(t * 2.6)), 2);
      fur = (.07 + .09 * bristle) * math.pow(math.sin(th * 28 + math.sin(t * 7 + th * 3) * .8).abs(), .6) +
          .02 * math.sin(th * 11 + t * 5);
    case MikkyForm.heart:
      final u = th + math.pi / 2;
      final hx = 16 * math.pow(math.sin(u), 3);
      final hy = 13 * math.cos(u) - 5 * math.cos(2 * u) - 2 * math.cos(3 * u) - math.cos(4 * u);
      const s = 1.2 / 16;
      x = hx * s;
      y = -(hy + 2.5) * s;
      fur = _fur(th, t, .04);
    case MikkyForm.dots:
      x = math.cos(th) * .55;
      y = math.sin(th) * .55;
      fur = _fur(th, t, .07);
    case MikkyForm.bang:
      // A soft, slightly bent bar.
      cy = -.35;
      final c = math.cos(th), s = math.sin(th);
      x = .40 * c.sign * math.pow(c.abs(), 2 / 2.2) + .05 * math.sin(th * 2 + t);
      y = cy + .95 * s.sign * math.pow(s.abs(), 2 / 2.2);
      fur = _fur(th, t, .05);
  }
  final wobble = (1 + .035 * math.sin(2 * th + t * 1.3) + .025 * math.sin(3 * th - t * .8 + 1)) * (1 + fur);
  return (x * wobble, cy + (y - cy) * wobble + _formOffsetY(f, t));
}

/// Where the eyes go on a form, and their scale.
(double, double, double) _eyeAnchor(MikkyForm f) => switch (f) {
      MikkyForm.cat => (0, 0, 1),
      MikkyForm.heart => (.34, -.25, .85),
      MikkyForm.furball => (.3, -.1, .8),
      MikkyForm.dots => (.17, -.08, .45),
      MikkyForm.bang => (.13, -.8, .5),
    };

/// The little fur balls that go with a form: center and radius. Not quite
/// the same size, not quite in step.
List<(double, double, double)> _satellites(MikkyForm f, double t) => switch (f) {
      MikkyForm.dots => [
          (-1.3, -math.sin(t * 5.5 - 1.1).abs() * .22, .5),
          (1.28, -math.sin(t * 5.5 + 1.1).abs() * .22, .46),
        ],
      MikkyForm.bang => [(.04, .92 + math.sin(t * 2.2 + .8) * .04, .3)],
      _ => const [],
    };

/// Outline of a fuzzy ball, in pixels.
Float64List _furBall(double cx, double cy, double radius, double t, int n) {
  final out = Float64List((n + 1) * 2);
  for (var i = 0; i <= n; i++) {
    final th = i / n * math.pi * 2;
    // Same fur as Mikky: they are bits of him.
    final f = 1 + _fur(th, t, .09) + .03 * math.sin(3 * th + t * 1.7);
    out[i * 2] = cx + math.cos(th) * radius * f;
    out[i * 2 + 1] = cy + math.sin(th) * radius * f;
  }
  return out;
}
