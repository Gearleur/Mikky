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

/// How his arms are drawn (trials, 2026-10-06). The stumps were the best
/// of the first five (« les moignons c'est ce qu'il y a de mieux »); the
/// others are ideas after the Luma of Mario Galaxy (« qui ressemble à Luma
/// mais pas vraiment Luma »): arms that are part of his outline, grown
/// out of it with no seam, like his ears.
enum ArmStyle {
  /// Short, thick and round stumps, joined to him.
  nub,

  /// Small points that grow out of his sides and lift a little, like a
  /// Luma's: the outline bends into them with no seam.
  star,

  /// Rounded stumps grown out of his outline, no seam: the stumps,
  /// melted into him.
  soft,

  /// Wide, soft flippers, a little low.
  fin,

  /// The points, and two tiny feet under him, like a Luma.
  starFeet,
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
    required this.arms,
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

  /// His arms and hands, when out: same format and transform as
  /// [contour], one with his body (the eyes stay on [contour]).
  final List<Float64List> arms;
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
  factory MikkyGeometry.of(Mikky mikky, double radius, {int points = 360, MikkyTuning? tuning}) => _build(
        pose: mikky.pose,
        time: mikky.time,
        form: mikky.form,
        morph: mikky.morph,
        eyeLeft: mikky.eyeLeft,
        eyeRight: mikky.eyeRight,
        badge: mikky.badge,
        particles: mikky.particles,
        radius: radius,
        points: points,
        tuning: tuning,
      );

  /// Mikky in a [pose] chosen from outside (a choreography), at [time] for
  /// what moves by itself (his fur), without his own life (no blinks,
  /// no breath, no badge).
  factory MikkyGeometry.posed(
    MikkyPose pose,
    double radius, {
    double time = 0,
    EyeShape eyeLeft = EyeShape.oval,
    EyeShape eyeRight = EyeShape.oval,
    MikkyForm form = MikkyForm.cat,
    double morph = 0,
    ArmStyle arms = ArmStyle.nub,
    int points = 360,
    MikkyTuning? tuning,
  }) =>
      _build(
        pose: pose,
        time: time,
        form: form,
        morph: morph,
        eyeLeft: eyeLeft,
        eyeRight: eyeRight,
        badge: null,
        particles: const [],
        armStyle: arms,
        radius: radius,
        points: points,
        tuning: tuning,
      );

  static MikkyGeometry _build({
    required MikkyPose pose,
    required double time,
    required MikkyForm form,
    required double morph,
    required EyeShape eyeLeft,
    required EyeShape eyeRight,
    required MikkyBadge? badge,
    ArmStyle armStyle = ArmStyle.nub,
    required List<MikkyParticle> particles,
    required double radius,
    required int points,
    MikkyTuning? tuning,
  }) {
    final tu = tuning ?? MikkyTuning.defaults;
    final p = pose;
    final t = time;
    final r = radius;
    final rx = r * MikkyShape.halfWidth, ry = r * MikkyShape.halfHeight;
    const ex = 2 / MikkyShape.exponent;
    final k = tu.bottomWiden;

    // m: how far into the form (may overshoot, like jelly); w: the same,
    // kept in 0..1 for what must not overshoot (ears, fur, eyes).
    final m = form == MikkyForm.cat ? 0.0 : morph;
    final w = m.clamp(0.0, 1.0);
    // The heart and the fur ball are still the mascot, a little changed:
    // they keep his outline and his eyes. The heart keeps its ears too; the
    // fur ball loses them and its fur stands out all around. Only the "!"
    // replaces him.
    final heart = form == MikkyForm.heart ? m : 0.0;
    final hw = heart.clamp(0.0, 1.2);
    final furry = form == MikkyForm.furball ? w : 0.0;
    final bang = form == MikkyForm.bang ? m : 0.0;
    final earMelt = form == MikkyForm.heart ? 0.0 : w;
    final eyeMelt = form == MikkyForm.bang ? w : 0.0;

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

    // Arms grown out of the outline (every style but the stumps).
    final armsOut = p[MikkyProp.arms].clamp(0.0, 1.0);
    final lobes = armStyle == ArmStyle.nub || armsOut <= .01
        ? const <_Lobe>[]
        : [
            for (final side in const [-1.0, 1.0])
              _Lobe.arm(
                armStyle,
                side,
                armsOut,
                side < 0 ? p[MikkyProp.handLeftX] : p[MikkyProp.handRightX],
                side < 0 ? p[MikkyProp.handLeftY] : p[MikkyProp.handRightY],
                side < 0 ? p[MikkyProp.handLeftTurn] : p[MikkyProp.handRightTurn],
                r,
              ),
            if (armStyle == ArmStyle.starFeet)
              for (final side in const [-1.0, 1.0]) _Lobe(math.pi / 2 - side * .55, .17 * r * armsOut, .3, _Lobe.round),
          ];

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
      if (py < 0) y -= earBump(x) * (1 - earMelt) * (-py / .3).clamp(0.0, 1.0);
      // His fur: a tuft on top of the head, fluffy cheeks, slowly waving.
      // Angles wrap around, so the right cheek is the same at both ends.
      final top = _bell(th, math.pi * 1.5, .16);
      final cheeks = _bell(th, .18, .22) + _bell(th, math.pi - .18, .22);
      final wave = math.sin(th * 40 + math.sin(t * 2.5) * .5).abs();
      final own = top * .09 + cheeks * .05;
      // The fur ball: the same fur, standing out a little more, all around,
      // rising a bit more here and there.
      final patch = .5 + .5 * math.sin(2 * th + t * .8 + 1) * math.sin(3 * th - t * 1.1 + 2);
      final allRound = (.065 + top * .04 + cheeks * .03) * (.75 + .5 * patch);
      final amount = form == MikkyForm.bang ? own * (1 - w) : own + (allRound - own) * furry;
      final fluff = 1 + amount * wave;
      x *= fluff;
      y *= fluff;
      if (lobes.isNotEmpty) {
        // Out along his outline's own direction, so the arm grows out of
        // it; gone as he turns into another form.
        final at = math.atan2(ry * py, rx * px);
        var grow = 0.0;
        for (final lobe in lobes) {
          grow += lobe.at(at);
        }
        grow *= 1 - w;
        if (grow > 0) {
          x += math.cos(at) * grow;
          y += math.sin(at) * grow;
        }
      }
      if (heart != 0 && py > 0) {
        // The bottom narrows a little and goes down to a soft, round point:
        // only a hint of a heart.
        x *= 1 - .26 * heart * math.pow(py, 1.4);
        y += heart * .16 * ry * math.pow(py, 3) * math.pow(1 - px.abs(), 2.5);
      } else if (heart != 0) {
        // The top gets a little wider, for the lobes.
        x *= 1 + .06 * heart * -py;
      } else if (bang != 0) {
        final (fx, fy) = _bangPoint(th, t);
        x += (fx * r - x) * bang;
        y += (fy * r - y) * bang;
      }
      contour[i * 2] = x;
      contour[i * 2 + 1] = y;
    }

    final eyes = <EyeGeometry>[];
    for (final side in const [-1.0, 1.0]) {
      final yaw = side * tu.eyeSpread + p.yaw;
      final pitch = tu.eyeElevation + p.pitch;
      final cp = math.cos(pitch);
      // Eye turned away from the viewer: hidden behind the head.
      if (math.cos(yaw) * cp < .05) continue;
      // The "!" has no eyes: they are gone before the bar takes shape, or
      // white bits stay in the middle of the thin bar.
      final grow = 1 - eyeMelt * 3;
      if (grow < .05) continue;
      final width = r * MikkyShape.eyeWidth * tu.eyeSize;
      final fullHeight = r * MikkyShape.eyeBaseHeight * tu.eyeElongation * tu.eyeSize;
      final shape = side < 0 ? eyeLeft : eyeRight;
      // Eyelids close the eyes that have lids; the other shapes keep their
      // look.
      final lid = shape == EyeShape.oval || shape == EyeShape.round || shape == EyeShape.tired ? p.open : 1.0;
      eyes.add(EyeGeometry(
        x: math.sin(yaw) * cp * rx * (1 - k * math.sin(pitch)),
        y: -math.sin(pitch) * ry,
        rotation: -.04 - p.yaw * .25,
        scaleX: math.max(.2, math.cos(yaw)) * p.eyeScale * grow,
        scaleY: math.max(.2, cp) * p.eyeScale * grow,
        width: width,
        height: math.max(width * .25, fullHeight * lid),
        fullHeight: fullHeight,
        shape: shape,
        side: side,
      ));
    }

    // The little fur ball that comes out of him: the dot of "!".
    final satellites = <Float64List>[
      if (form == MikkyForm.bang && w > 0)
        _furBall(.03 * r * _easeOut(w), (.88 + math.sin(t * 2.2 + .8) * .035) * r * _easeOut(w), .27 * r * w, t, 120),
    ];

    // His arms: tucked into his body, they come out of his sides and hang
    // there; from there the hands go where the pose sends them.
    final show = p[MikkyProp.arms].clamp(0.0, 1.0);
    final arms = <Float64List>[
      if (show > .01 && armStyle == ArmStyle.nub)
        for (final side in const [-1.0, 1.0])
          ..._arm(
            side,
            show,
            side < 0 ? p[MikkyProp.handLeftX] : p[MikkyProp.handRightX],
            side < 0 ? p[MikkyProp.handLeftY] : p[MikkyProp.handRightY],
            side < 0 ? p[MikkyProp.handLeftTurn] : p[MikkyProp.handRightTurn],
            r,
            t,
            armStyle,
          ),
    ];

    return MikkyGeometry._(
      radius: r,
      time: t,
      contour: contour,
      satellites: satellites,
      arms: arms,
      eyes: eyes,
      translateX: p.offsetX * r,
      translateY: p.offsetY * r,
      tilt: p.tilt,
      scaleX: p.scaleX,
      scaleY: p.scaleY,
      badge: badge,
      badgeX: r * 1.12 + p.offsetX * r,
      badgeY: -r * .95 + p.offsetY * r,
      particles: [
        for (final q in particles) MikkyParticle(q.kind, q.x * r, q.y * r, q.size * r, q.alpha, q.rotation),
      ],
    );
  }
}

// ------------------------------------------------------------------ forms
//
// In units of R, centered on Mikky, y down. Never perfect: outlines wobble
// slowly and keep fur.

double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();

/// Bell curve around the angle [center], measured the short way round.
double _bell(double th, double center, double width) {
  var d = (th - center) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  return math.exp(-math.pow(d / width, 2));
}

/// Slow wobble of an outline: never quite the same shape.
double _wobble(double th, double t, [double amount = 1]) =>
    1 + amount * (.035 * math.sin(2 * th + t * 1.3) + .025 * math.sin(3 * th - t * .8 + 1));

/// Fine fur all around an outline, uneven, moving (the "!").
double _fur(double th, double t, double amount) =>
    amount * math.sin(th * 34 + math.sin(t * 3 + th * 5) * .6).abs() + amount * .3 * math.sin(th * 13 - t * 4);

/// Lumpy, lopsided outline of a ball: never a circle. [seed] makes each
/// ball lopsided in its own way.
double _lumpy(double th, double t, double seed) =>
    1 +
    .06 * math.sin(2 * th + .7 + seed) +
    .045 * math.sin(3 * th + 2.1 + seed * 2 + math.sin(t * .6) * .3) +
    .025 * math.sin(5 * th + 4 + seed * 3 + t * .4);

/// Point of the bar of "!" for the angle [th] of the cat's outline (same
/// parameter, so the change does not twist): wide and round at the top,
/// thinner at the bottom, a little bent and leaning, well apart from its
/// dot.
(double, double) _bangPoint(double th, double t) {
  final c = math.cos(th), s = math.sin(th);
  const top = -1.42, bottom = .2;
  const cy = (top + bottom) / 2, hy = (bottom - top) / 2;
  final y = cy + hy * s.sign * math.pow(s.abs(), 2 / 2.6);
  final v = (y - top) / (bottom - top);
  final half = .43 + (.16 - .43) * v;
  final x = half * c.sign * math.pow(c.abs(), 2 / 2.6) + .05 * math.sin(v * math.pi + t * .7) - (y - cy) * .07;
  final g = _wobble(th, t, .6) * (1 + _fur(th, t, .035));
  return (x * g, cy + (y - cy) * g + math.sin(t * 2.2) * .03);
}

/// One stump, on [side] (-1 left), [show] out of his body: a short thick
/// tube from his shoulder toward the hand, and a round end; [hx], [hy]
/// move the hand from its place (units of [r]), [turn] turns it. The
/// parts overlap: they are joined when drawn.
List<Float64List> _arm(double side, double show, double hx, double hy, double turn, double r, double t, ArmStyle style) {
  // The shoulder, inside his side; the hand tucked in, then hanging
  // beside him; short: it stays near the body.
  final sx = side * .84 * r, sy = .12 * r;
  final hxFull = side * (.7 + .42 * show) * r + hx * r, hyFull = (.3 + .32 * show) * r + hy * r;
  final ex = sx + (hxFull - sx) * .58, ey = sy + (hyFull - sy) * .58;
  const w0 = .36, w1 = .3;
  const n = 20;
  final left = <double>[], right = <double>[];
  final dx = ex - sx, dy = ey - sy;
  final len = math.max(1e-6, math.sqrt(dx * dx + dy * dy));
  final nx = -dy / len, ny = dx / len;
  for (var i = 0; i <= n; i++) {
    final q = i / n;
    final bx = sx + dx * q, by = sy + dy * q;
    final half = (w0 + (w1 - w0) * q) * r / 2;
    left.addAll([bx + nx * half, by + ny * half]);
    right.addAll([bx - nx * half, by - ny * half]);
  }
  final tube = Float64List(left.length + right.length)..setAll(0, left);
  for (var i = 0; i < right.length ~/ 2; i++) {
    final j = right.length ~/ 2 - 1 - i;
    tube[left.length + i * 2] = right[j * 2];
    tube[left.length + i * 2 + 1] = right[j * 2 + 1];
  }
  return [tube, _blob(ex, ey, w1 / 2 * r, w1 / 2 * r, math.atan2(dy, dx) + turn, t, side)];
}

/// A bump grown out of his outline (an arm, a foot): around the angle
/// [angle] (from his center, y down), [length] pixels out at its middle,
/// [halfWidth] radians to each side, with the [profile] of its shape.
class _Lobe {
  const _Lobe(this.angle, this.length, this.halfWidth, this.profile);

  /// An arm of [style] on [side]: where its hand is (as for the stumps:
  /// [hx], [hy] from its place at his side) gives its direction, and how
  /// far, its length; [turn] bends it a little more (a wave).
  factory _Lobe.arm(ArmStyle style, double side, double show, double hx, double hy, double turn, double r) {
    final (rest, length, halfWidth, profile) = switch (style) {
      ArmStyle.star || ArmStyle.starFeet => (.02, .36, .3, point),
      ArmStyle.soft => (.12, .32, .36, round),
      ArmStyle.fin => (.42, .3, .55, flat),
      ArmStyle.nub => (0.0, 0.0, .5, round),
    };
    // On the right side, then mirrored: where the hand is, seen from his
    // center.
    final tx = math.cos(rest) * 1.15 + hx * side, ty = math.sin(rest) * 1.15 + hy;
    // Not over his ears, not under him.
    final a = (math.atan2(ty, tx) + turn * .5).clamp(-.35, 1.2);
    final reach = math.pow((math.sqrt(tx * tx + ty * ty) / 1.15).clamp(.6, 1.6), .6).toDouble();
    return _Lobe(side > 0 ? a : math.pi - a, length * r * show * reach, halfWidth, profile);
  }

  final double angle, length, halfWidth;
  final double Function(double u) profile;

  /// A point with soft, hollow sides: it grows out of the outline with no
  /// seam (a Luma's arms).
  static double point(double u) => math.pow(1 - u, 1.35).toDouble();

  /// Round at the end, no seam at the base.
  static double round(double u) => math.pow(1 - u * u, 2).toDouble();

  /// Wide and flat at the end: a flipper.
  static double flat(double u) => math.pow(math.cos(u * math.pi / 2), 1.1).toDouble();

  /// How far the outline goes out at the angle [at].
  double at(double at) {
    var d = (at - angle) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    final u = d.abs() / halfWidth;
    return u >= 1 ? 0 : length * profile(u);
  }
}

/// A small soft oval (a hand), lopsided like him, [fur] for a tuft.
Float64List _blob(double cx, double cy, double rx, double ry, double angle, double t, double seed, {double fur = .02}) {
  const n = 40;
  final out = Float64List((n + 1) * 2);
  final c = math.cos(angle), s = math.sin(angle);
  for (var i = 0; i <= n; i++) {
    final th = i / n * math.pi * 2;
    final f = (1 + _fur(th, t + seed, fur)) * (1 + .5 * (_lumpy(th, t, seed + 4) - 1));
    final x = math.cos(th) * rx * f, y = math.sin(th) * ry * f;
    out[i * 2] = cx + x * c - y * s;
    out[i * 2 + 1] = cy + x * s + y * c;
  }
  return out;
}

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
