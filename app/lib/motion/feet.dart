import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import '../ui/tokens.dart';

/// Feet (a trial, 2026-10-06, after Kirby's: « des pattes ovales, un peu
/// grosses… de la même couleur que Mikky mais qu'on les voie »; the rule
/// « no feet » holds until one is chosen): two ovals in front of the
/// bottom of his body, his black, set apart from him by a [FootLook].
enum FootShape {
  kirby('Comme Kirby', 'Deux gros ovales, un peu inclinés, le bout vers l’extérieur.', (x: .48, y: .86, rx: .44, ry: .27, tilt: .28)),
  small('Petits', 'Plus petits, plus serrés, presque sous lui.', (x: .38, y: .92, rx: .3, ry: .19, tilt: .14)),
  wide('Écartés', 'Bien écartés sur les côtés, plus inclinés.', (x: .64, y: .8, rx: .36, ry: .23, tilt: .5)),
  plump('Dodus', 'Ronds et épais, droits, comme posés.', (x: .42, y: .9, rx: .38, ry: .3, tilt: 0));

  const FootShape(this.label, this.note, this.oval);

  final String label, note;

  /// The right foot, in units of his radius from his center: its middle,
  /// its half width and height, how much its outer end lifts (radians).
  final ({double x, double y, double rx, double ry, double tilt}) oval;
}

/// How a black foot shows on his black body.
enum FootLook {
  line('Un trait', 'Un trait fin autour du pied : clair en sombre, une découpe blanche en clair.'),
  sheen('Un reflet', 'Pas de trait : un reflet doux sur le dessus du pied, le noir dessous.'),
  both('Trait et reflet', 'Les deux.');

  const FootLook(this.label, this.note);

  final String label, note;
}

/// Mikky standing on [shape] feet, seen with [look].
class FeetScene extends StatelessWidget {
  const FeetScene(this.shape, this.look, {super.key, this.size = const Size(170, 150), this.radius = 36});

  final FootShape shape;
  final FootLook look;
  final Size size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final mui = MikkyUi.of(context);
    return Container(
      width: size.width,
      height: size.height,
      color: mui.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708),
      child: CustomPaint(painter: _FeetPainter(shape, look, radius, mui.isLight)),
    );
  }
}

class _FeetPainter extends CustomPainter {
  _FeetPainter(this.shape, this.look, this.radius, this.light);

  final FootShape shape;
  final FootLook look;
  final double radius;
  final bool light;

  static const _ink = Color(0xFF0C0C0E);

  @override
  void paint(Canvas canvas, Size size) {
    final theme = light ? MikkyTheme.light : MikkyTheme.dark;
    final r = radius;
    final center = Offset(size.width / 2, size.height * .48);
    final g = MikkyGeometry.posed(MikkyPose(), r);
    MikkyPainter(geometry: g, center: center, rim: theme.mikkyRim, statusColor: theme.status, foreground: theme.foreground, showBadge: false)
        .paint(canvas, size);

    final o = shape.oval;
    for (final side in const [-1.0, 1.0]) {
      final c = center + Offset(g.translateX + side * o.x * r, g.translateY + o.y * r);
      final rect = Rect.fromCenter(center: Offset.zero, width: o.rx * 2 * r, height: o.ry * 2 * r);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      // The outer end lifts.
      canvas.rotate(-side * o.tilt);
      final foot = Path()..addOval(rect);
      final fill = Paint()..color = _ink;
      if (look != FootLook.line) {
        // Lit from above and from inside: lighter up there, his black below.
        fill.shader = ui.Gradient.radial(
          Offset(-side * o.rx * r * .25, -o.ry * r * .55),
          o.rx * r * 1.25,
          [Color.lerp(_ink, const Color(0xFFFFFFFF), light ? .3 : .22)!, _ink],
          const [0, 1],
        );
      }
      canvas.drawPath(foot, fill);
      if (look != FootLook.sheen) {
        canvas.drawPath(
          foot,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, r * (light ? .07 : .05))
            ..color = light ? const Color(0xFFFFFFFF) : const Color(0x66FFFFFF),
        );
      }
      if (look != FootLook.line) {
        // A small bright spot on top.
        canvas.drawOval(
          Rect.fromCenter(center: Offset(-side * o.rx * r * .3, -o.ry * r * .45), width: o.rx * r * .55, height: o.ry * r * .32),
          Paint()
            ..color = Color(light ? 0x40FFFFFF : 0x30FFFFFF)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .03),
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FeetPainter old) => old.shape != shape || old.look != look || old.radius != radius || old.light != light;
}
