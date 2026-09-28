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

/// One tuft of fur of the balls: a thick curved lock from a base inside the
/// body to a round tip, in the body's local frame (same transform as the
/// outline).
class FurStrand {
  const FurStrand(this.baseX, this.baseY, this.controlX, this.controlY, this.tipX, this.tipY, this.width);

  final double baseX, baseY, controlX, controlY, tipX, tipY;

  /// Width at the base; the lock tapers to a round tip.
  final double width;
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
    required this.fur,
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

  /// Other bits of him (the dot of "!"), same format and same transform as
  /// [contour]. Eyes are only on [contour].
  final List<Float64List> satellites;

  /// Long fur of the balls, drawn with the body (same transform).
  final List<FurStrand> fur;
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

    // m: how far into the form (may overshoot, like jelly); w: the same,
    // kept in 0..1 for what must not overshoot (ears, tufts, eyes).
    final form = mikky.form;
    final m = form == MikkyForm.cat ? 0.0 : mikky.morph;
    final w = m.clamp(0.0, 1.0);
    // The heart is still the mascot, only a little squeezed into a heart:
    // it keeps its ears, tufts and eyes. The other forms replace him.
    final heart = form == MikkyForm.heart ? m : 0.0;
    final hw = heart.clamp(0.0, 1.2);
    final melt = form == MikkyForm.heart ? 0.0 : w;

    double earBump(double x) {
      var best = 0.0;
      for (final side in const [-1.0, 1.0]) {
        final twitch = side < 0 ? p.earLeft : p.earRight;
        // Raised ears grow and lean in a little; lowered ones go flat to the
        // side, like a cat's, instead of just shrinking.
        final down = math.max(0.0, -twitch);
        // In the heart, the ears are its two round lobes: a bit lower,
        // wider, further apart.
        final center = side * rx * tu.earCenter +
            p.yaw * rx * .28 +
            side * twitch * rx * .06 +
            side * down * rx * .3 +
            side * hw * rx * .04;
        final d = x - center;
        final halfWidth = (d * side > 0 ? MikkyShape.earOuterHalfWidth : MikkyShape.earInnerHalfWidth) *
            rx *
            tu.earWidth *
            (1 + down * .35) *
            (1 + hw * .18);
        final tri = (1 - d.abs() / halfWidth).clamp(0.0, 1.0);
        final grow = (twitch > 0 ? 1 + twitch * .9 : 1 + twitch * .6) * (1 - hw * .12);
        // The far ear gets a bit shorter when the head turns.
        final height = tu.earHeight * r * grow * (1 - .18 * (side * p.yaw).clamp(0.0, 1.0));
        // Still ears, only rounder.
        final curve = MikkyShape.earCurve + (.6 - MikkyShape.earCurve) * hw;
        best = math.max(best, math.max(0.0, height) * math.pow(tri, curve));
      }
      return best;
    }

    final contour = Float64List((points + 1) * 2);
    for (var i = 0; i <= points; i++) {
      final th = i / points * math.pi * 2;
      final c = math.cos(th), s = math.sin(th);
      final px = c.sign * math.pow(c.abs(), ex);
      final py = s.sign * math.pow(s.abs(), ex);
      var x = rx * px * (1 + k * py);
      var y = ry * py;
      // The ears melt into the form. Lowered ears reach the sides: they fade
      // out toward the middle of the side, so the outline stays smooth where
      // it starts and ends.
      if (py < 0) y -= earBump(x) * (1 - melt) * (-py / .3).clamp(0.0, 1.0);
      // Tufts: one on top of the head, fluffy cheeks, slowly waving. Angles
      // wrap around, so the right cheek is the same at both ends.
      final top = _bell(th, math.pi * 1.5, .16);
      final cheeks = _bell(th, .18, .22) + _bell(th, math.pi - .18, .22);
      final fluff = 1 + (top * .09 + cheeks * .05) * math.sin(th * 40 + math.sin(t * 2.5) * .5).abs() * (1 - melt);
      x *= fluff;
      y *= fluff;
      if (heart != 0 && py > 0) {
        // The bottom narrows a little and goes down to a soft, round point:
        // only a hint of a heart.
        x *= 1 - .26 * heart * math.pow(py, 1.4);
        y += heart * .16 * ry * math.pow(py, 3) * math.pow(1 - px.abs(), 2.5);
      } else if (heart != 0) {
        // The top gets a little wider, for the lobes.
        x *= 1 + .06 * heart * -py;
      } else if (m != 0) {
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
      // on a form, both eyes stay). The heart keeps the cat's eyes: melt is
      // 0 for it.
      if (math.cos(yaw) * cp < .05 && melt < .5) continue;
      final width = r * MikkyShape.eyeWidth * tu.eyeSize;
      final fullHeight = r * MikkyShape.eyeBaseHeight * tu.eyeElongation * tu.eyeSize;
      final shape = side < 0 ? mikky.eyeLeft : mikky.eyeRight;
      // Eyelids only close ovals; the other shapes keep their look.
      final lid = shape == EyeShape.oval || shape == EyeShape.tired ? p.open : 1.0;
      final catX = math.sin(yaw) * cp * rx * (1 - k * math.sin(pitch));
      final catY = -math.sin(pitch) * ry;
      final (ax, ay, scale) = anchor;
      // Forms without eyes: the eyes are gone before the form takes shape,
      // or white bits stay in the middle of the thin "!" bar.
      final grow = scale == 0 ? 1 - melt * 3 : 1 + (scale - 1) * melt;
      if (grow < .05) continue;
      final formX = (side * ax + p.yaw * .25) * r;
      final formY = (ay - p.pitch * .2) * r + _formOffsetY(form, t) * r;
      final sx = math.max(.2, math.cos(yaw)) * p.eyeScale;
      final sy = math.max(.2, cp) * p.eyeScale;
      eyes.add(EyeGeometry(
        x: catX + (formX - catX) * melt,
        y: catY + (formY - catY) * melt,
        rotation: (-.04 - p.yaw * .25) * (1 - melt),
        scaleX: (sx + (p.eyeScale - sx) * melt) * grow,
        scaleY: (sy + (p.eyeScale - sy) * melt) * grow,
        width: width,
        height: math.max(width * .25, fullHeight * lid),
        fullHeight: fullHeight,
        shape: shape,
        side: side,
      ));
    }

    // The little fur ball that comes out of him (the dot of "!").
    final satellites = <Float64List>[
      for (final (cx, cy, cr) in _satellites(form, t))
        // Enough points for the fine fur, or it turns into lumps.
        _furBall(cx * r * _easeOut(w), cy * r * _easeOut(w), cr * r * w, t + cx * 3, 120),
    ];

    return MikkyGeometry._(
      radius: r,
      time: t,
      contour: contour,
      satellites: satellites,
      fur: _furStrands(form, t, r, w, form == MikkyForm.ball ? 34 : 46, contour),
      eyes: eyes,
      translateX: p.offsetX * r,
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

/// Bell curve around the angle [center], measured the short way round.
double _bell(double th, double center, double width) {
  var d = (th - center) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  return math.exp(-math.pow(d / width, 2));
}

/// Deterministic pseudo-random number in [0, 1) for [k].
double _hash(double k) {
  final v = math.sin(k * 12.9898 + 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

/// 0 on the ground, 1 at the top of the hop.
double _hopHeight(double t) => math.sin(t * 5.2).abs();

/// Hops of the body in a form.
double _formOffsetY(MikkyForm f, double t) => switch (f) {
      MikkyForm.ball => -_hopHeight(t) * .34,
      MikkyForm.bang => math.sin(t * 2.2) * .03,
      _ => 0,
    };

/// Slow wobble of an outline: never quite the same shape.
double _wobble(double th, double t, [double amount = 1]) =>
    1 + amount * (.035 * math.sin(2 * th + t * 1.3) + .025 * math.sin(3 * th - t * .8 + 1));

/// Fine fur all around an outline, uneven, moving (heart, "!").
double _fur(double th, double t, double amount) =>
    amount * math.sin(th * 34 + math.sin(t * 3 + th * 5) * .6).abs() + amount * .3 * math.sin(th * 13 - t * 4);

/// Radius of the body of a ball, under its fur.
double _ballBody(MikkyForm f) => f == MikkyForm.ball ? .58 : .78;

/// A soft ripple on the body, under the tufts.
double _undercoat(double th, double t) => .02 * math.sin(th * 9 + t * .7) + .012 * math.sin(th * 14 - t * 1.3);

/// The hopping ball: squashed when it lands, round in the air, and up.
(double, double) _ballPlace(MikkyForm f, double t, double x, double y) {
  if (f != MikkyForm.ball) return (x, y);
  final contact = math.pow(1 - _hopHeight(t), 6).toDouble();
  return (x * (1 + .14 * contact), y * (1 - .14 * contact) + _ballBody(f) * .14 * contact + _formOffsetY(f, t));
}

/// The fur of the balls, tuft by tuft: not many, thick, round-ended, a
/// little curved, of different lengths, going every way from the body and
/// overlapping, swaying a little, each rising on its own in patches that
/// wander (it bristles). They grow out as he turns into the ball.
List<FurStrand> _furStrands(MikkyForm f, double t, double r, double w, int count, Float64List contour) {
  if (w <= 0 || (f != MikkyForm.furball && f != MikkyForm.ball)) return const [];
  final ball = f == MikkyForm.ball;
  final length = (ball ? .26 : .34) * r;
  final seed = ball ? 300.0 : 0.0;
  final grow = _easeOut(w);
  // The tufts grow from the body as it is drawn now (while it changes, hops
  // and squashes), so they never come apart from it.
  final n = contour.length ~/ 2 - 1;
  var cx = 0.0, cy = 0.0;
  for (var i = 0; i < n; i++) {
    cx += contour[i * 2];
    cy += contour[i * 2 + 1];
  }
  cx /= n;
  cy /= n;
  final out = <FurStrand>[];
  for (var j = 0; j < count; j++) {
    final h = j + seed;
    final th = 2 * math.pi * (j + (_hash(h + .1) - .5) * .7) / count + t * .05;
    final i = ((th / (2 * math.pi)) % 1 * n).round() % n;
    final ex = contour[i * 2] - cx, ey = contour[i * 2 + 1] - cy;
    // The base is inside the body, so the lock melts into it.
    final inside = .72 + .12 * _hash(h + .2);
    final bx = cx + ex * inside, by = cy + ey * inside;
    var len = length * (.5 + .5 * math.pow(_hash(h + .3), .8));
    if (_hash(h + .4) > .9) len *= 1.35;
    final own = .5 + .5 * math.sin(t * (.8 + 1.6 * _hash(h + .5)) + 6.283 * _hash(h + .6));
    final patch = .5 + .5 * math.sin(2 * th + t * .8 + 1) * math.sin(3 * th - t * 1.1 + 2);
    len *= (.6 + .4 * own * (.4 + .6 * patch)) * grow;
    final sway = .1 * math.sin(t * (1.1 + _hash(h + .7)) + 6.283 * _hash(h + .8));
    final dir = math.atan2(ey, ex) + (_hash(h + .9) - .5) * .7 + sway;
    final curl = (_hash(h + 1.1) - .5) * .7;
    final dx = math.cos(dir), dy = math.sin(dir);
    final reach = math.sqrt(ex * ex + ey * ey) * (1 - inside) + len;
    out.add(FurStrand(
      bx,
      by,
      bx + dx * reach * .5 - dy * curl * reach * .3,
      by + dy * reach * .5 + dx * curl * reach * .3,
      bx + dx * reach,
      by + dy * reach,
      r * (.16 + .08 * _hash(h + 1.2)) * grow,
    ));
  }
  return out;
}

/// Lumpy, lopsided outline of a ball: never a circle. [seed] makes each
/// ball lopsided in its own way.
double _lumpy(double th, double t, double seed) =>
    1 +
    .06 * math.sin(2 * th + .7 + seed) +
    .045 * math.sin(3 * th + 2.1 + seed * 2 + math.sin(t * .6) * .3) +
    .025 * math.sin(5 * th + 4 + seed * 3 + t * .4);

/// Point of the form's outline for the angle [th] of the cat's outline:
/// same parameter, so the change does not twist.
(double, double) _formPoint(MikkyForm f, double th, double t) {
  final c = math.cos(th), s = math.sin(th);
  switch (f) {
    // The heart deforms the cat's own outline (see [MikkyGeometry.of]).
    case MikkyForm.cat || MikkyForm.heart:
      return (0, 0);
    // The balls: a lumpy body with a short undercoat. Their long fur is
    // drawn on top, strand by strand (see [_furStrands]).
    case MikkyForm.furball:
      final r = _ballBody(f) * _lumpy(th, t, 0) + _undercoat(th, t);
      return (c * r, s * r);
    case MikkyForm.ball:
      final r = _ballBody(f) * _lumpy(th, t, 1.7) + _undercoat(th, t + 3);
      return _ballPlace(f, t, c * r, s * r);
    case MikkyForm.bang:
      // The bar of "!": wide and round at the top, thinner at the bottom,
      // a little bent and leaning. Well apart from its dot.
      const top = -1.42, bottom = .2;
      const cy = (top + bottom) / 2, hy = (bottom - top) / 2;
      final y = cy + hy * s.sign * math.pow(s.abs(), 2 / 2.6);
      final v = (y - top) / (bottom - top);
      final half = .43 + (.16 - .43) * v;
      final x = half * c.sign * math.pow(c.abs(), 2 / 2.6) + .05 * math.sin(v * math.pi + t * .7) - (y - cy) * .07;
      final g = _wobble(th, t, .6) * (1 + _fur(th, t, .035));
      return (x * g, cy + (y - cy) * g + _formOffsetY(f, t));
  }
}

/// Where the eyes go on a form, and their scale (0: no eyes).
(double, double, double) _eyeAnchor(MikkyForm f) => switch (f) {
      MikkyForm.cat => (0, 0, 1),
      MikkyForm.heart => (0, 0, 1), // keeps the cat's eyes
      MikkyForm.furball => (.3, -.1, .8),
      MikkyForm.ball => (.2, -.1, .55),
      // The "!" is only the sign.
      MikkyForm.bang => (.13, -.9, 0),
    };

/// The little fur balls that go with a form: center and radius.
List<(double, double, double)> _satellites(MikkyForm f, double t) => switch (f) {
      MikkyForm.bang => [(.03, .88 + math.sin(t * 2.2 + .8) * .035, .27)],
      _ => const [],
    };

/// Outline of a small, lopsided, softly furry ball, in pixels.
Float64List _furBall(double cx, double cy, double radius, double t, int n) {
  final out = Float64List((n + 1) * 2);
  for (var i = 0; i <= n; i++) {
    final th = i / n * math.pi * 2;
    final f = _lumpy(th, t, 3.1) * (1 + _fur(th, t + 5, .06));
    out[i * 2] = cx + math.cos(th) * radius * f;
    out[i * 2 + 1] = cy + math.sin(th) * radius * f;
  }
  return out;
}
