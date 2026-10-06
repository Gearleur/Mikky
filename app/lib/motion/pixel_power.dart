import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../ui/pixel_fx.dart';
import '../ui/tokens.dart';
import 'launch.dart';

/// How pixelated Mikky gets when he uses his powers (2026-10-06, « garder
/// notre DA pixel… plus magicien 16 bits, 32 bits »).
enum PixelPowerStyle {
  /// Big pixels (3 px), four shades and no blending, a dark outline like
  /// a sprite, a halo in steps.
  bits16('16 bits', 'Gros pixels, quatre teintes sans mélange, un contour sombre de sprite, un halo en marches.'),

  /// Small pixels (2 px), eight shades mixed by an ordered dither, a
  /// softer stepped halo.
  bits32('32 bits', 'Petits pixels, huit teintes mêlées par une trame, un halo plus doux, toujours en marches.'),

  /// The 16 bits, with a magician's pixel stars and sparks around him.
  mage16('Magicien 16 bits', 'Le 16 bits, avec des étoiles et des étincelles en pixels autour de lui : il lance un sort.'),

  /// The 32 bits, with the stars and a dithered aura.
  mage32('Magicien 32 bits', 'Le 32 bits, avec les étoiles et une aura tramée qui monte de lui.');

  const PixelPowerStyle(this.label, this.note);

  final String label, note;

  bool get big => this == bits16 || this == mage16;
  bool get magic => this == mage16 || this == mage32;
}

/// Mikky lit by his powers, drawn in pixels with one of our palettes (the
/// signature orange or blue).
class PixelPowerScene extends StatelessWidget {
  const PixelPowerScene(this.style, this.palette, {super.key, this.size = const Size(170, 140), this.radius = 30});

  final PixelPowerStyle style;
  final PixelFxPalette palette;
  final Size size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: size.width,
      height: size.height,
      color: ui.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708),
      child: CustomPaint(painter: _PixelPowerPainter(style, palette, radius, ui.isLight)),
    );
  }
}

class _PixelPowerPainter extends CustomPainter {
  _PixelPowerPainter(this.style, this.palette, this.radius, this.light);

  final PixelPowerStyle style;
  final PixelFxPalette palette;
  final double radius;
  final bool light;

  /// 4 × 4 ordered dither.
  static const _bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = style.big ? 3.0 : 2.0;
    final cols = (size.width / cell).floor(), rows = (size.height / cell).floor();
    final center = Offset(size.width / 2, size.height * .58);
    final r = radius;
    final g = geometryAt(Powers.pose, 0, r);
    final body = Path()..addPolygon([for (var i = 0; i < g.pointCount; i++) Offset(g.contour[i * 2], g.contour[i * 2 + 1])], true);

    // Each cell: inside him or not, and how far from his light.
    final inside = Uint8List(cols * rows);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final p = Offset((x + .5) * cell, (y + .5) * cell) - center;
        final local = Offset((p.dx - g.translateX) / g.scaleX, (p.dy - g.translateY) / g.scaleY);
        if (body.contains(local)) inside[y * cols + x] = 1;
      }
    }
    bool isIn(int x, int y) => x >= 0 && y >= 0 && x < cols && y < rows && inside[y * cols + x] == 1;

    // The shades: almost white in the middle, then the palette, to its
    // darkest at the edge.
    final heart = Color.lerp(palette.levels.first, const Color(0xFFFFFFFF), .3)!;
    final shades = [heart, ...palette.levels];
    final paint = Paint()..isAntiAlias = false;

    // The halo in steps: rings of cells around him, fainter and fainter,
    // checkered at the end.
    final dist = Uint8List(cols * rows);
    var ring = [for (var y = 0; y < rows; y++) for (var x = 0; x < cols; x++) if (isIn(x, y)) (x, y)];
    final steps = style.big ? 4 : 6;
    for (var d = 1; d <= steps; d++) {
      final next = <(int, int)>[];
      for (final (x, y) in ring) {
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
          final i = ny * cols + nx;
          if (inside[i] == 1 || dist[i] != 0) continue;
          dist[i] = d;
          next.add((nx, ny));
        }
      }
      ring = next;
    }
    final glow = palette.levels[1];
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final d = dist[y * cols + x];
        if (d == 0) continue;
        var a = (1 - (d - 1) / steps) * .55;
        // The 32 bits: a dither instead of fainter cells; the last rings
        // checkered either way.
        if (!style.big && _bayer[(y % 4) * 4 + x % 4] / 16 > a * 1.6) continue;
        if (style.big && d == steps && (x + y).isOdd) continue;
        if (!style.big) a = .45;
        paint.color = glow.withValues(alpha: a);
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }

    // His body, shaded from his light (up, in the middle), dithered in
    // 32 bits.
    final light = center + Offset(g.translateX, g.translateY - r * .25);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (!isIn(x, y)) continue;
        final edge = !isIn(x + 1, y) || !isIn(x - 1, y) || !isIn(x, y + 1) || !isIn(x, y - 1);
        final p = Offset((x + .5) * cell, (y + .5) * cell);
        final t = ((p - light).distance / (r * 1.25)).clamp(0.0, 1.0);
        Color color;
        if (style.big) {
          // A sprite's dark outline, four flat shades inside.
          color = edge ? shades.last : shades[(t * 4).floor().clamp(0, 3)];
        } else {
          final f = t * (shades.length - 1);
          var k = f.floor();
          if (f - k > _bayer[(y % 4) * 4 + x % 4] / 16) k++;
          color = shades[k.clamp(0, shades.length - 1)];
          if (edge) color = Color.lerp(color, heart, .35)!;
        }
        paint.color = color;
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }

    // His eyes, dark cells: white ones were lost in his light.
    for (final eye in g.eyes) {
      final c = math.cos(eye.rotation), s = math.sin(eye.rotation);
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < cols; x++) {
          final p = Offset((x + .5) * cell, (y + .5) * cell) - center;
          final bx = (p.dx - g.translateX) / g.scaleX - eye.x, by = (p.dy - g.translateY) / g.scaleY - eye.y;
          final ex = (bx * c + by * s) / eye.scaleX, ey = (-bx * s + by * c) / eye.scaleY;
          final rx = eye.width / 2, ry = eye.height / 2;
          if ((ex * ex) / (rx * rx) + (ey * ey) / (ry * ry) > 1) continue;
          paint.color = const Color(0xFF1A0508);
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }

    // The magician: pixel stars and sparks around him.
    if (style.magic) {
      final px = cell;
      void star(Offset at, int arm, Color color) {
        final o = Offset((at.dx / px).floorToDouble() * px, (at.dy / px).floorToDouble() * px);
        paint.color = const Color(0xFFFFFFFF);
        canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, px, px), paint);
        for (var k = 1; k <= arm; k++) {
          paint.color = color.withValues(alpha: 1 - (k - 1) / (arm + 1));
          for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            canvas.drawRect(Rect.fromLTWH(o.dx + dx * k * px, o.dy + dy * k * px, px, px), paint);
          }
        }
      }

      star(center + Offset(-r * 1.75, -r * .9), 3, palette.levels.first);
      star(center + Offset(r * 1.65, -r * 1.25), 2, palette.levels[1]);
      star(center + Offset(r * 1.95, r * .35), 1, palette.levels.first);
      star(center + Offset(-r * 1.5, r * .55), 1, palette.levels[1]);
      // Sparks rising from him.
      final rng = math.Random(5);
      for (var i = 0; i < 14; i++) {
        final o = center + Offset((rng.nextDouble() - .5) * r * 2.6, -r * (.9 + rng.nextDouble() * 1.1));
        paint.color = shades[rng.nextInt(3)].withValues(alpha: .5 + .5 * rng.nextDouble());
        canvas.drawRect(Rect.fromLTWH((o.dx / px).floorToDouble() * px, (o.dy / px).floorToDouble() * px, px, px), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelPowerPainter old) => old.style != style || old.palette != palette || old.radius != radius || old.light != light;
}
