import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// A rounded shape painted like the CSS of the prototypes: outer shadows
/// (only outside the shape, as CSS draws them), a color or a vertical
/// gradient, then inset shadows (the top light edge, the hollow of a
/// well, a ring). Every control of the kit is one of these.
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    this.color,
    this.gradient,
    this.shadows = const [],
    this.radius,
    this.width,
    this.height,
    this.padding,
    this.child,
  });

  final Color? color;
  final Gradient? gradient;
  final List<CssShadow> shadows;

  /// Null: a pill (half the height).
  final double? radius;
  final double? width, height;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: SurfacePainter(color: color, gradient: gradient, shadows: shadows, radius: radius),
        child: SizedBox(
          width: width,
          height: height,
          child: padding == null ? child : Padding(padding: padding!, child: child),
        ),
      );
}

class SurfacePainter extends CustomPainter {
  const SurfacePainter({this.color, this.gradient, this.shadows = const [], this.radius});

  final Color? color;
  final Gradient? gradient;
  final List<CssShadow> shadows;
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius ?? size.shortestSide / 2;
    final shape = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    final outer = shadows.where((s) => !s.inset).toList();
    if (outer.isNotEmpty) {
      canvas.save();
      canvas.clipPath(Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(shape.outerRect.inflate(200))
        ..addRRect(shape));
      for (final s in outer.reversed) {
        final paint = Paint()..color = s.color;
        if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.sigma);
        canvas.drawRRect(shape.shift(Offset(s.dx, s.dy)).inflate(s.spread), paint);
      }
      canvas.restore();
    }
    if (color != null || gradient != null) {
      final paint = Paint();
      if (gradient != null) {
        paint.shader = gradient!.createShader(Offset.zero & size);
      } else {
        paint.color = color!;
      }
      canvas.drawRRect(shape, paint);
    }
    final inner = shadows.where((s) => s.inset).toList();
    if (inner.isNotEmpty) {
      canvas.save();
      canvas.clipRRect(shape);
      for (final s in inner.reversed) {
        final paint = Paint()..color = s.color;
        if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.sigma);
        final hole = shape.shift(Offset(s.dx, s.dy)).deflate(s.spread);
        canvas.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(shape.outerRect.inflate(s.blur * 2 + 20))
            ..addRRect(hole),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SurfacePainter old) =>
      old.color != color || old.gradient != gradient || old.shadows != shadows || old.radius != radius;
}
