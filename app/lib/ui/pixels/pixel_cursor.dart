import 'package:flutter/widgets.dart';

import 'pixel_fx.dart';

/// The navigation star and its short trail, shared by page dots and sliders.
/// Only moves while its owner animates; no idle clock or decorative loop.
void paintPixelCursor(
  Canvas canvas, {
  required Offset center,
  required double size,
  required PixelFxPalette palette,
  double trail = 0,
}) {
  final length = trail.abs();
  if (length > .5) {
    final paint = Paint();
    for (var k = 1; k <= 4; k++) {
      final back = size / 2 - 1 + k * length.clamp(0.0, 9.0) / 2.2;
      final fade = (1 - k / 5) * (length / 6).clamp(0.0, 1.0);
      paint.color = palette.levels[k < 3 ? 1 : 2].withValues(alpha: fade);
      final side = k < 3 ? 2.0 : 1.5;
      canvas.drawRect(
        Rect.fromCenter(center: center.translate(-trail.sign * back, 0), width: side, height: side),
        paint,
      );
    }
  }
  canvas.save();
  canvas.translate(center.dx - size / 2, center.dy - size / 2);
  paintPixelGrid(canvas, Size.square(size), 7, gap: .02, (x, y) {
    final level = pixelLevel(CalmFirework.frame(1, x - 3, y - 3));
    return level == null ? null : palette.levels[level];
  });
  canvas.restore();
}
