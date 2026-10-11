import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The island's shape in a child of it: [shape] (in the child's
/// coordinates, past the screen's edge) with the shader's corners — a
/// curve of radius [radius] and power [power] (2: a circle's).
class IslandClip extends CustomClipper<Path> {
  const IslandClip(this.shape, this.radius, [this.power = 2]);

  final Rect shape;
  final double radius, power;

  @override
  Path getClip(Size size) {
    final r = math.max(0.0, math.min(radius, shape.shortestSide / 2));
    if (r == 0) return Path()..addRect(shape);
    final path = Path();
    // Each corner from its center: (cos t, sin t) raised to the power
    // 2 / n lies on |x|ⁿ + |y|ⁿ = 1.
    const steps = 12;
    void corner(Offset c, double from) {
      for (var i = 0; i <= steps; i++) {
        final t = from + math.pi / 2 * i / steps;
        final x = math.cos(t), y = math.sin(t);
        final p = c + Offset(x.sign * math.pow(x.abs(), 2 / power), y.sign * math.pow(y.abs(), 2 / power)) * r;
        if (i == 0 && from == math.pi) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }

    corner(Offset(shape.left + r, shape.top + r), math.pi);
    corner(Offset(shape.right - r, shape.top + r), 1.5 * math.pi);
    corner(Offset(shape.right - r, shape.bottom - r), 0);
    corner(Offset(shape.left + r, shape.bottom - r), .5 * math.pi);
    return path..close();
  }

  @override
  bool shouldReclip(IslandClip old) => old.shape != shape || old.radius != radius || old.power != power;
}

/// The island's shape as a rounded rectangle (see [IslandClip]).
class IslandRoundClip extends CustomClipper<RRect> {
  const IslandRoundClip(this.shape, this.radius);

  final Rect shape;
  final double radius;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(shape, Radius.circular(math.max(0.0, math.min(radius, shape.shortestSide / 2))));

  @override
  bool shouldReclip(IslandRoundClip old) => old.shape != shape || old.radius != radius;
}
