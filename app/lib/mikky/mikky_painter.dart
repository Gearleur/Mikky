import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:mikky_engine/mikky_engine.dart';

const _ink = Color(0xFF0C0C0E);
const _eyeWhite = Color(0xFFF7F7F7);

/// Draws one frame of Mikky's geometry, centered on [center].
class MikkyPainter extends CustomPainter {
  MikkyPainter({required this.geometry, required this.center, this.rim});

  final MikkyGeometry geometry;
  final Offset center;

  /// Outline color, to separate Mikky from a dark background.
  final Color? rim;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final r = g.radius;
    final points = [
      for (var i = 0; i < g.pointCount; i++) Offset(g.contour[i * 2], g.contour[i * 2 + 1]),
    ];
    final body = Path()..addPolygon(points, true);

    canvas.save();
    canvas.translate(center.dx + g.translateX, center.dy + g.translateY);
    canvas.rotate(g.tilt);
    canvas.scale(g.scaleX, g.scaleY);

    canvas.drawPath(body, Paint()..color = _ink);
    final rim = this.rim;
    if (rim != null) {
      canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, r * .045)
          ..color = rim,
      );
    }

    canvas.save();
    canvas.clipPath(body);
    final eyePaint = Paint()..color = _eyeWhite;
    for (final eye in g.eyes) {
      canvas.save();
      canvas.translate(eye.x, eye.y);
      canvas.rotate(eye.rotation);
      canvas.scale(eye.scaleX, eye.scaleY);
      switch (eye.shape) {
        case EyeShape.oval:
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: eye.width, height: eye.height), eyePaint);
        case EyeShape.happy:
          final arcRadius = eye.width * .7;
          canvas.drawArc(
            Rect.fromCircle(center: Offset(0, r * MikkyShape.eyeHeight * .2), radius: arcRadius),
            math.pi * 1.12,
            math.pi * .76,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = r * .15
              ..color = _eyeWhite,
          );
      }
      canvas.restore();
    }
    canvas.restore();
    canvas.restore();
  }

  // A new painter is built for each frame, with a new geometry.
  @override
  bool shouldRepaint(MikkyPainter oldDelegate) => true;
}
