import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import '../ui/tokens.dart';
import 'launch.dart';

/// Feet (a trial, 2026-10-06, after Kirby's; the Kirby ones kept: two big
/// ovals in front of the bottom of his body, a little tilted, his black;
/// the rule « no feet » holds until they are chosen), set apart from his
/// body by a [FootLook].
abstract final class Feet {
  /// The right foot, in units of his radius from his center: its middle,
  /// its half width and height, its tilt (radians).
  static const x = .48, y = .86, rx = .44, ry = .27, tilt = .28;
}

/// How a black foot shows on his black body (« les traits c'est ce qu'il
/// y a de mieux mais je suis dubitatif, trouve d'autres choses »).
enum FootLook {
  line('Un trait', 'Un trait fin tout autour : clair en sombre, une découpe blanche en clair.'),
  inBody('Un trait sur lui', 'Le trait seulement là où le pied passe devant son corps : un pli, plus des lunettes.'),
  topRim('Un liseré', 'Une lumière fine sur le haut du pied seulement, qui s’éteint vers ses bouts.'),
  blueRim('Un liseré bleu', 'Le même liseré en notre bleu, avec une petite lueur.'),
  pixelRim('Un liseré en pixels', 'Des petits carrés de lumière le long du haut du pied : notre DA pixel.');

  const FootLook(this.label, this.note);

  final String label, note;
}

/// Mikky on his feet, seen with [look], in [pose] (his arms; null: none).
class FeetScene extends StatelessWidget {
  const FeetScene(this.look, {super.key, this.pose, this.size = const Size(170, 150), this.radius = 36});

  final FootLook look;
  final Choreography? pose;
  final Size size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final mui = MikkyUi.of(context);
    return Container(
      width: size.width,
      height: size.height,
      color: mui.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708),
      child: CustomPaint(painter: _FeetPainter(look, pose, radius, mui.isLight)),
    );
  }
}

class _FeetPainter extends CustomPainter {
  _FeetPainter(this.look, this.pose, this.radius, this.light);

  final FootLook look;
  final Choreography? pose;
  final double radius;
  final bool light;

  static const _ink = Color(0xFF0C0C0E);
  static const _blue = Color(0xFF0F84FA);
  static final _still = Choreography(name: 'Debout', duration: 1, tracks: const {});

  @override
  void paint(Canvas canvas, Size size) {
    final theme = light ? MikkyTheme.light : MikkyTheme.dark;
    final r = radius;
    final center = Offset(size.width / 2, size.height * .46);
    final g = geometryAt(pose ?? _still, 0, r);
    MikkyPainter(geometry: g, center: center, rim: theme.mikkyRim, statusColor: theme.status, foreground: theme.foreground, showBadge: false)
        .paint(canvas, size);

    // His body where it is drawn: the trait « sur lui » stays inside it.
    final m = Matrix4.identity()
      ..translateByDouble(center.dx + g.translateX, center.dy + g.translateY, 0, 1)
      ..rotateZ(g.tilt)
      ..scaleByDouble(g.scaleX, g.scaleY, 1, 1);
    final body = (Path()..addPolygon([for (var i = 0; i < g.pointCount; i++) Offset(g.contour[i * 2], g.contour[i * 2 + 1])], true))
        .transform(Float64List.fromList(m.storage));

    final line = light ? const Color(0xFFFFFFFF) : const Color(0x80FFFFFF);
    for (final side in const [-1.0, 1.0]) {
      final c = center + Offset(g.translateX + side * Feet.x * r, g.translateY + Feet.y * r);
      final rect = Rect.fromCenter(center: Offset.zero, width: Feet.rx * 2 * r, height: Feet.ry * 2 * r);
      final foot = Path()..addOval(rect);
      // Draws in the foot's own frame; [clip]: only over his body.
      void inFoot(void Function() draw, {bool clip = false}) {
        canvas.save();
        if (clip) canvas.clipPath(body);
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-side * Feet.tilt);
        draw();
        canvas.restore();
      }

      inFoot(() => canvas.drawPath(foot, Paint()..color = _ink));
      // His rim (in dark) goes on round his feet, where they stick out of
      // him: without it, they vanish in the dark.
      final rim = theme.mikkyRim;
      if (rim != null && look != FootLook.line) {
        canvas.save();
        canvas.clipPath(Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addPath(body, Offset.zero));
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-side * Feet.tilt);
        canvas.drawPath(foot, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, r * .045)
          ..color = rim);
        canvas.restore();
      }
      final width = math.max(1.2, r * (light ? .07 : .05));
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = line;
      switch (look) {
        case FootLook.line:
          inFoot(() => canvas.drawPath(foot, stroke));
        case FootLook.inBody:
          inFoot(() => canvas.drawPath(foot, stroke), clip: true);
        case FootLook.topRim || FootLook.blueRim:
          final color = look == FootLook.blueRim ? _blue : line;
          inFoot(() {
            if (look == FootLook.blueRim) {
              canvas.drawArc(rect, math.pi * 1.1, math.pi * .8, false, Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = width * 2.2
                ..strokeCap = StrokeCap.round
                ..color = _blue.withValues(alpha: .45)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .05));
            }
            // Brightest in the middle of the top, gone toward the ends.
            canvas.drawArc(rect, math.pi * 1.08, math.pi * .84, false, Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..strokeCap = StrokeCap.round
              ..shader = ui.Gradient.linear(Offset(-rect.width / 2, 0), Offset(rect.width / 2, 0), [
                color.withValues(alpha: 0),
                color,
                color,
                color.withValues(alpha: 0),
              ], const [0, .3, .7, 1]));
          });
        case FootLook.pixelRim:
          inFoot(() {
            const n = 14;
            final px = math.max(2.0, (r * .055).roundToDouble());
            for (var i = 1; i < n; i++) {
              final a = math.pi * (1.08 + .84 * i / n);
              final q = (i / n - .5).abs() * 2;
              final o = Offset(math.cos(a) * rect.width / 2, math.sin(a) * rect.height / 2);
              canvas.drawRect(
                Rect.fromCenter(center: Offset(o.dx.roundToDouble(), o.dy.roundToDouble()), width: px, height: px),
                Paint()
                  ..isAntiAlias = false
                  ..color = (light ? const Color(0xFFFFFFFF) : _blue).withValues(alpha: 1 - q * .75),
              );
            }
          });
      }
    }
  }

  @override
  bool shouldRepaint(_FeetPainter old) => old.look != look || old.pose != pose || old.radius != radius || old.light != light;
}
