import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import '../ui/tokens.dart';
import 'launch.dart';

/// Feet (a test, 2026-10-06, after Kirby's; kept aside, « des pieds que
/// très rarement »): two big ovals in front of the bottom of his body, a
/// little tilted, his black, set apart from him by a row of little squares
/// of light along their top (« le liseré pixelisé c'est le mieux »). With
/// feet come his arms (« s'il y a les pieds, il y a les bras »).
abstract final class Feet {
  /// The right foot, in units of his radius from his center: its middle,
  /// its half width and height, its tilt (radians).
  static const x = .48, y = .86, rx = .44, ry = .27, tilt = .28;
}

/// Mikky on his feet, his arms in [pose].
class FeetScene extends StatelessWidget {
  const FeetScene(this.pose, {super.key, this.size = const Size(170, 150), this.radius = 36});

  final Choreography pose;
  final Size size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final mui = MikkyUi.of(context);
    return Container(
      width: size.width,
      height: size.height,
      color: mui.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708),
      child: CustomPaint(painter: _FeetPainter(pose, radius, mui.isLight)),
    );
  }
}

class _FeetPainter extends CustomPainter {
  _FeetPainter(this.pose, this.radius, this.light);

  final Choreography pose;
  final double radius;
  final bool light;

  static const _ink = Color(0xFF0C0C0E);
  static const _blue = Color(0xFF0F84FA);

  @override
  void paint(Canvas canvas, Size size) {
    final theme = light ? MikkyTheme.light : MikkyTheme.dark;
    final r = radius;
    final center = Offset(size.width / 2, size.height * .46);
    final g = geometryAt(pose, 0, r);
    MikkyPainter(geometry: g, center: center, rim: theme.mikkyRim, statusColor: theme.status, foreground: theme.foreground, showBadge: false)
        .paint(canvas, size);

    // His body where it is drawn: his rim goes on round his feet only
    // where they stick out of him.
    final m = Matrix4.identity()
      ..translateByDouble(center.dx + g.translateX, center.dy + g.translateY, 0, 1)
      ..rotateZ(g.tilt)
      ..scaleByDouble(g.scaleX, g.scaleY, 1, 1);
    final body = (Path()..addPolygon([for (var i = 0; i < g.pointCount; i++) Offset(g.contour[i * 2], g.contour[i * 2 + 1])], true))
        .transform(Float64List.fromList(m.storage));

    for (final side in const [-1.0, 1.0]) {
      final c = center + Offset(g.translateX + side * Feet.x * r, g.translateY + Feet.y * r);
      final rect = Rect.fromCenter(center: Offset.zero, width: Feet.rx * 2 * r, height: Feet.ry * 2 * r);
      final foot = Path()..addOval(rect);
      // Draws in the foot's own frame; [outside]: only off his body.
      void inFoot(void Function() draw, {bool outside = false}) {
        canvas.save();
        if (outside) {
          canvas.clipPath(Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(Offset.zero & size)
            ..addPath(body, Offset.zero));
        }
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-side * Feet.tilt);
        draw();
        canvas.restore();
      }

      inFoot(() => canvas.drawPath(foot, Paint()..color = _ink));
      final rim = theme.mikkyRim;
      if (rim != null) {
        inFoot(
          () => canvas.drawPath(foot, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, r * .045)
            ..color = rim),
          outside: true,
        );
      }
      // The liseré: little squares of light along the top, brightest in
      // the middle.
      inFoot(() {
        const n = 14;
        final px = math.max(2.0, (r * .055).roundToDouble());
        final paint = Paint()..isAntiAlias = false;
        for (var i = 1; i < n; i++) {
          final a = math.pi * (1.08 + .84 * i / n);
          final q = (i / n - .5).abs() * 2;
          final o = Offset(math.cos(a) * rect.width / 2, math.sin(a) * rect.height / 2);
          paint.color = (light ? const Color(0xFFFFFFFF) : _blue).withValues(alpha: 1 - q * .75);
          canvas.drawRect(Rect.fromCenter(center: Offset(o.dx.roundToDouble(), o.dy.roundToDouble()), width: px, height: px), paint);
        }
      });
    }
  }

  @override
  bool shouldRepaint(_FeetPainter old) => old.pose != pose || old.radius != radius || old.light != light;
}
