import 'dart:math' as math;
import 'dart:typed_data';

import 'mikky.dart';

/// Mikky's validated silhouette ("G" + tufts, spec §3), in units of the
/// radius R.
abstract final class MikkyShape {
  /// Superellipse exponent.
  static const exponent = 2.4;
  static const halfWidth = 1.06;
  static const halfHeight = .92;

  /// How much wider the bottom is than the top.
  static const bottomWiden = .055;

  /// Ears: bumps of the same outline.
  static const earCenter = .60; // × half width
  static const earOuterHalfWidth = .40; // × half width
  static const earInnerHalfWidth = .44; // × half width
  static const earHeight = .55; // × R
  static const earCurve = .85;

  /// Eyes: ovals on a sphere, no pupil.
  static const eyeSpread = .30; // radians, each side
  static const eyeElevation = .26; // radians
  static const eyeWidth = .21; // × R
  static const eyeHeight = .50 * 1.25; // × R
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
    required this.shape,
  });

  /// Center.
  final double x, y;

  /// Apply in this order: translate(x, y), rotate, scale.
  final double rotation, scaleX, scaleY;

  /// Size of the oval before scaling; [height] already includes the eyelid.
  final double width, height;
  final EyeShape shape;
}

/// Everything needed to draw Mikky at one instant, in pixels.
///
/// To draw: translate([translateX], [translateY]) from Mikky's anchor,
/// rotate([tilt]), scale([scaleX], [scaleY]); fill [contour]; clip to it and
/// draw [eyes].
class MikkyGeometry {
  MikkyGeometry._({
    required this.radius,
    required this.contour,
    required this.eyes,
    required this.translateX,
    required this.translateY,
    required this.tilt,
    required this.scaleX,
    required this.scaleY,
  });

  final double radius;

  /// Closed outline: x0, y0, x1, y1, ... (y down), centered on Mikky.
  final Float64List contour;
  final List<EyeGeometry> eyes;
  final double translateX, translateY, tilt, scaleX, scaleY;

  int get pointCount => contour.length ~/ 2;

  /// Geometry of [mikky] drawn with radius [radius] pixels, with [points]
  /// points on the outline.
  factory MikkyGeometry.of(Mikky mikky, double radius, {int points = 360}) {
    final p = mikky.pose;
    final t = mikky.time;
    final r = radius;
    final rx = r * MikkyShape.halfWidth, ry = r * MikkyShape.halfHeight;
    const ex = 2 / MikkyShape.exponent;
    const k = MikkyShape.bottomWiden;

    double earBump(double x) {
      var best = 0.0;
      for (final side in const [-1.0, 1.0]) {
        final twitch = side < 0 ? p.earLeft : p.earRight;
        final center = side * rx * MikkyShape.earCenter + p.yaw * rx * .28 + side * twitch * rx * .06;
        final d = x - center;
        final halfWidth = (d * side > 0 ? MikkyShape.earOuterHalfWidth : MikkyShape.earInnerHalfWidth) * rx;
        final tri = (1 - d.abs() / halfWidth).clamp(0.0, 1.0);
        // The far ear gets a bit shorter when the head turns.
        final height =
            MikkyShape.earHeight * r * (1 + twitch * .9) * (1 - .18 * (side * p.yaw).clamp(0.0, 1.0));
        best = math.max(best, height * math.pow(tri, MikkyShape.earCurve));
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
      if (py < 0) y -= earBump(x);
      // Tufts: one on top of the head, fluffy cheeks, slowly waving.
      final top = math.exp(-math.pow((th - math.pi * 1.5) / .16, 2));
      final cheeks = math.exp(-math.pow((th - .18) / .22, 2)) + math.exp(-math.pow((th - (math.pi - .18)) / .22, 2));
      final fluff = 1 + (top * .09 + cheeks * .05) * math.sin(th * 40 + math.sin(t * 2.5) * .5).abs();
      contour[i * 2] = x * fluff;
      contour[i * 2 + 1] = y * fluff;
    }

    final eyes = <EyeGeometry>[];
    for (final side in const [-1.0, 1.0]) {
      final yaw = side * MikkyShape.eyeSpread + p.yaw;
      final pitch = MikkyShape.eyeElevation + p.pitch;
      final cp = math.cos(pitch);
      // Eye turned away from the viewer: hidden behind the head.
      if (math.cos(yaw) * cp < .05) continue;
      final width = r * MikkyShape.eyeWidth;
      final fullHeight = r * MikkyShape.eyeHeight;
      eyes.add(EyeGeometry(
        x: math.sin(yaw) * cp * rx * (1 - k * math.sin(pitch)),
        y: -math.sin(pitch) * ry,
        rotation: -.04 - p.yaw * .25,
        scaleX: math.max(.2, math.cos(yaw)) * p.eyeScale,
        scaleY: math.max(.2, cp) * p.eyeScale,
        width: width,
        height: math.max(width * .25, fullHeight * p.open),
        shape: mikky.eyes,
      ));
    }

    return MikkyGeometry._(
      radius: r,
      contour: contour,
      eyes: eyes,
      translateX: p.offsetX * r,
      translateY: p.offsetY * r,
      tilt: p.tilt,
      scaleX: p.scaleX,
      scaleY: p.scaleY,
    );
  }
}
