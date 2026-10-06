import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../ui/pixel_fx.dart';
import '../ui/tokens.dart';
import 'launch.dart';

/// How Mikky looks in pixels when he uses his powers (2026-10-06: « garder
/// notre DA pixel… magicien »; the 16 and 32 bits were « trop pixelisés »,
/// « fais-les en version 128 bits »): fine pixels, many shades mixed by a
/// dither, the glow around him in bigger steps so the pixels still show.
enum PixelPowerStyle {
  /// Pixels of 1, sixteen shades in a fine dither, a light rim inside, a
  /// halo in steps of 2.
  bits128('128 bits', 'Pixels fins, seize teintes mêlées par une trame fine, une lumière le long de son bord, un halo en marches.'),

  /// The 128 bits, with a magician's pixel stars and sparks around him.
  mage128('Magicien 128 bits', 'Le 128 bits, avec des étoiles et des étincelles en pixels autour de lui : il lance un sort.');

  const PixelPowerStyle(this.label, this.note);

  final String label, note;

  bool get magic => this == mage128;
}

/// The colors of his pixel powers: our two signature ones, then others,
/// each from its brightest to its darkest.
abstract final class PixelPowerColors {
  static const all = <(String, PixelFxPalette)>[
    ('Orange', PixelFxPalette.signatureOrange),
    ('Bleu', PixelFxPalette.signatureBlue),
    ('Rouge fluo', PixelFxPalette('Rouge fluo', [Color(0xFFFF6B81), Color(0xFFFF2D55), Color(0xFFD90F3C), Color(0xFF8A0624)])),
    ('Rose', PixelFxPalette('Rose', [Color(0xFFFF9BE0), Color(0xFFFF5FC8), Color(0xFFD6339E), Color(0xFF7A1460)])),
    ('Violet', PixelFxPalette('Violet', [Color(0xFFE3A8FF), Color(0xFFBF5AF2), Color(0xFF8E2DC8), Color(0xFF4A1478)])),
    ('Vert', PixelFxPalette('Vert', [Color(0xFF8DFFB8), Color(0xFF34E07A), Color(0xFF14A855), Color(0xFF0A5C2E)])),
    ('Cyan', PixelFxPalette('Cyan', [Color(0xFF9BF0FF), Color(0xFF33D6FF), Color(0xFF109CC8), Color(0xFF0A4F6E)])),
    ('Jaune', PixelFxPalette('Jaune', [Color(0xFFFFF1A0), Color(0xFFFFD23F), Color(0xFFE0A30F), Color(0xFF8A5A00)])),
  ];
}

/// Mikky lit by his powers, in pixels, in one [palette].
class PixelPowerScene extends StatelessWidget {
  const PixelPowerScene(this.style, this.palette, {super.key, this.size = const Size(170, 150), this.radius = 36});

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
      child: CustomPaint(painter: _PixelPowerPainter(style, palette, radius, size)),
    );
  }
}

class _PixelPowerPainter extends CustomPainter {
  _PixelPowerPainter(this.style, this.palette, this.radius, this.size);

  final PixelPowerStyle style;
  final PixelFxPalette palette;
  final double radius;
  final Size size;

  /// Each one drawn once into an image (thousands of pixels: drawn again
  /// at each frame, they made the board lag), shared by both themes.
  static final _images = <(PixelPowerStyle, PixelFxPalette, double, Size), ui.Image>{};

  /// 4 × 4 ordered dither.
  static const _bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  static double _dither(int x, int y) => (_bayer[(y % 4) * 4 + x % 4] + .5) / 16;

  @override
  void paint(Canvas canvas, Size _) {
    final image = _images.putIfAbsent((style, palette, radius, size), () {
      final recorder = ui.PictureRecorder();
      _draw(Canvas(recorder));
      final picture = recorder.endRecording();
      final image = picture.toImageSync(size.width.ceil(), size.height.ceil());
      picture.dispose();
      return image;
    });
    // Its pixels kept sharp when the screen scales it.
    canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.none);
  }

  void _draw(Canvas canvas) {
    final cols = size.width.floor(), rows = size.height.floor();
    final center = Offset(size.width / 2, size.height * .58);
    final r = radius;
    final g = geometryAt(ArmPoses.all.first, 0, r);
    final body = Path()..addPolygon([for (var i = 0; i < g.pointCount; i++) Offset(g.contour[i * 2], g.contour[i * 2 + 1])], true);
    Offset local(double x, double y) => Offset((x - center.dx - g.translateX) / g.scaleX, (y - center.dy - g.translateY) / g.scaleY);

    // Inside him, pixel by pixel; only around him.
    final inside = Uint8List(cols * rows);
    final box = body.getBounds().shift(center).inflate(2);
    for (var y = math.max(0, box.top.floor()); y < math.min(rows, box.bottom.ceil()); y++) {
      for (var x = math.max(0, box.left.floor()); x < math.min(cols, box.right.ceil()); x++) {
        if (body.contains(local(x + .5, y + .5))) inside[y * cols + x] = 1;
      }
    }
    bool isIn(int x, int y) => x >= 0 && y >= 0 && x < cols && y < rows && inside[y * cols + x] == 1;
    final paint = Paint()..isAntiAlias = false;

    // The halo, on a grid of 2: rings around him, a dither thinning them
    // out (the pixels show there).
    const big = 2;
    final bc = (cols / big).ceil(), br = (rows / big).ceil();
    final dist = Uint8List(bc * br);
    final seen = Uint8List(bc * br);
    var ring = <(int, int)>[];
    for (var y = 0; y < br; y++) {
      for (var x = 0; x < bc; x++) {
        if (isIn(x * big, y * big) || isIn(x * big + 1, y * big + 1)) {
          seen[y * bc + x] = 1;
          ring.add((x, y));
        }
      }
    }
    const steps = 9;
    for (var d = 1; d <= steps; d++) {
      final next = <(int, int)>[];
      for (final (x, y) in ring) {
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= bc || ny >= br) continue;
          final i = ny * bc + nx;
          if (seen[i] == 1) continue;
          seen[i] = 1;
          dist[i] = d;
          next.add((nx, ny));
        }
      }
      ring = next;
    }
    final glow = palette.levels[1];
    for (var y = 0; y < br; y++) {
      for (var x = 0; x < bc; x++) {
        final d = dist[y * bc + x];
        if (d == 0) continue;
        final k = 1 - (d - 1) / steps;
        if (_dither(x, y) > k * 1.15) continue;
        paint.color = Color.lerp(glow, palette.levels.first, k * .5)!.withValues(alpha: .25 + .4 * k);
        canvas.drawRect(Rect.fromLTWH(x * big * 1.0, y * big * 1.0, big * 1.0, big * 1.0), paint);
      }
    }

    // His body: sixteen shades from his light (up, in the middle) to his
    // edge, mixed by a fine dither; a light rim along his edge.
    final heart = Color.lerp(palette.levels.first, const Color(0xFFFFFFFF), .45)!;
    final ramp = [heart, ...palette.levels];
    Color shade(double t) {
      final f = t.clamp(0.0, 1.0) * (ramp.length - 1);
      final i = math.min(f.floor(), ramp.length - 2);
      return Color.lerp(ramp[i], ramp[i + 1], f - i)!;
    }

    final light = center + Offset(g.translateX, g.translateY - r * .25);
    const levels = 16;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (!isIn(x, y)) continue;
        final t = ((Offset(x + .5, y + .5) - light).distance / (r * 1.3)).clamp(0.0, 1.0);
        final f = t * (levels - 1);
        var step = f.floor();
        if (f - step > _dither(x, y)) step++;
        var color = shade(step / (levels - 1));
        final edge = !isIn(x + 1, y) || !isIn(x - 1, y) || !isIn(x, y + 1) || !isIn(x, y - 1);
        final near = !isIn(x + 2, y) || !isIn(x - 2, y) || !isIn(x, y + 2) || !isIn(x, y - 2);
        if (edge) {
          color = Color.lerp(color, heart, .6)!;
        } else if (near && _dither(x, y) < .5) {
          color = Color.lerp(color, heart, .3)!;
        }
        paint.color = color;
        canvas.drawRect(Rect.fromLTWH(x * 1.0, y * 1.0, 1, 1), paint);
      }
    }

    // His eyes, dark: white ones were lost in his light.
    paint.color = const Color(0xFF1A0508);
    for (final eye in g.eyes) {
      final c = math.cos(eye.rotation), s = math.sin(eye.rotation);
      final rx = eye.width / 2, ry = eye.height / 2;
      final ec = center + Offset(g.translateX + eye.x * g.scaleX, g.translateY + eye.y * g.scaleY);
      for (var y = (ec.dy - ry * 2).floor(); y < (ec.dy + ry * 2).ceil(); y++) {
        for (var x = (ec.dx - rx * 3).floor(); x < (ec.dx + rx * 3).ceil(); x++) {
          final p = local(x + .5, y + .5);
          final bx = p.dx - eye.x, by = p.dy - eye.y;
          final ex = (bx * c + by * s) / eye.scaleX, ey = (-bx * s + by * c) / eye.scaleY;
          if ((ex * ex) / (rx * rx) + (ey * ey) / (ry * ry) > 1) continue;
          canvas.drawRect(Rect.fromLTWH(x * 1.0, y * 1.0, 1, 1), paint);
        }
      }
    }

    // The magician: pixel stars (a cross, its tips fading, a spark in the
    // corners) and sparks rising from him.
    if (style.magic) {
      void star(Offset at, int arm, double px) {
        final o = Offset((at.dx / px).floorToDouble() * px, (at.dy / px).floorToDouble() * px);
        paint.color = const Color(0xFFFFFFFF);
        canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, px, px), paint);
        for (var k = 1; k <= arm; k++) {
          paint.color = Color.lerp(heart, palette.levels[1], (k - 1) / arm)!.withValues(alpha: 1 - (k - 1) / (arm + 1));
          for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            canvas.drawRect(Rect.fromLTWH(o.dx + dx * k * px, o.dy + dy * k * px, px, px), paint);
          }
        }
        paint.color = palette.levels.first.withValues(alpha: .6);
        for (final (dx, dy) in const [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
          canvas.drawRect(Rect.fromLTWH(o.dx + dx * px, o.dy + dy * px, px, px), paint);
        }
      }

      star(center + Offset(-r * 1.55, -r * .85), 4, 2);
      star(center + Offset(r * 1.45, -r * 1.1), 3, 2);
      star(center + Offset(r * 1.75, r * .4), 2, 1.5);
      star(center + Offset(-r * 1.35, r * .6), 2, 1.5);
      star(center + Offset(r * .2, -r * 1.65), 2, 1.5);
      final rng = math.Random(5);
      for (var i = 0; i < 26; i++) {
        final o = center + Offset((rng.nextDouble() - .5) * r * 2.4, -r * (.7 + rng.nextDouble() * 1.2));
        final s = rng.nextDouble() < .3 ? 2.0 : 1.0;
        paint.color = ramp[rng.nextInt(3)].withValues(alpha: .45 + .55 * rng.nextDouble());
        canvas.drawRect(Rect.fromLTWH(o.dx.floorToDouble(), o.dy.floorToDouble(), s, s), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelPowerPainter old) => old.style != style || old.palette != palette || old.radius != radius || old.size != size;
}
