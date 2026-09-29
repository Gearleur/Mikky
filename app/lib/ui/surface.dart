import 'dart:collection';
import 'dart:ui' as dui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// A rounded shape painted like the CSS of the prototypes: outer shadows
/// (only outside the shape, as CSS draws them), a color or a vertical
/// gradient, then inset shadows (the top light edge, the hollow of a
/// well, a ring). Every control of the kit is one of these.
class Surface extends StatelessWidget {
  const Surface({super.key, this.color, this.gradient, this.shadows = const [], this.radius, this.width, this.height, this.padding, this.child});

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
    painter: SurfacePainter(
      color: color,
      gradient: gradient,
      shadows: shadows,
      radius: radius,
      pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
    ),
    child: SizedBox(
      width: width,
      height: height,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    ),
  );
}

/// Paints a [Surface]. Cheap on purpose: Impeller redraws the whole window
/// at every frame of any animation, so
/// - outer shadows are plain blurred rounded rects (a fast path), clipped
///   out of the shape only when the fill lets them show through;
/// - inset shadows (a blurred path) are drawn once into an image, per size,
///   and that image is reused.
class SurfacePainter extends CustomPainter {
  const SurfacePainter({this.color, this.gradient, this.shadows = const [], this.radius, this.pixelRatio = 1});

  final Color? color;
  final Gradient? gradient;
  final List<CssShadow> shadows;
  final double? radius;
  final double pixelRatio;

  bool get _opaque {
    final g = gradient;
    if (g != null) return g.colors.every((c) => c.a == 1);
    final c = color;
    return c != null && c.a == 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius ?? size.shortestSide / 2;
    final shape = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    final outer = shadows.where((s) => !s.inset).toList();
    if (outer.isNotEmpty) {
      final clip = !_opaque;
      if (clip) {
        canvas.save();
        canvas.clipPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(shape.outerRect.inflate(200))
            ..addRRect(shape),
        );
      }
      for (final s in outer.reversed) {
        final paint = Paint()..color = s.color;
        if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.sigma);
        canvas.drawRRect(shape.shift(Offset(s.dx, s.dy)).inflate(s.spread), paint);
      }
      if (clip) canvas.restore();
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
    if (inner.isNotEmpty && !size.isEmpty) {
      final image = _InsetCache.image(size, r, inner, pixelRatio);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.low,
      );
    }
  }

  @override
  bool shouldRepaint(SurfacePainter old) =>
      old.color != color || old.gradient != gradient || !listEquals(old.shadows, shadows) || old.radius != radius || old.pixelRatio != pixelRatio;
}

/// Inset shadows drawn once per size and reused (a small LRU).
abstract final class _InsetCache {
  static final LinkedHashMap<(double, double, double, double, int), dui.Image> _images = LinkedHashMap();
  static const _max = 256;

  static dui.Image image(Size size, double r, List<CssShadow> shadows, double ratio) {
    final key = (size.width, size.height, r, ratio, Object.hashAll(shadows));
    final hit = _images.remove(key);
    if (hit != null) return _images[key] = hit;
    final recorder = dui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    final shape = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    canvas.clipRRect(shape);
    for (final s in shadows.reversed) {
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
    final picture = recorder.endRecording();
    final image = picture.toImageSync((size.width * ratio).ceil(), (size.height * ratio).ceil());
    picture.dispose();
    _images[key] = image;
    if (_images.length > _max) _images.remove(_images.keys.first)?.dispose();
    return image;
  }
}
