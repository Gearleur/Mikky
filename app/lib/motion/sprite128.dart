import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../ui/pixels/pixel_fx.dart';

/// The 128-bit look (2026-10-06: « dès que Mikky change de couleur, il
/// doit être en 128 bits… les animations deviennent en 128 bits »): a
/// shape drawn in fine pixels, sixteen shades of [palette] mixed by an
/// ordered dither from its [light] (brightest) to [reach] away, a light
/// rim along its edge, [holes] in a dark color (his eyes), and a halo of
/// [halo] steps of bigger pixels, thinned by the dither. [fade] dissolves
/// it pixel by pixel, in the dither's order (as the magic goes out of him:
/// no muddy half colors). Drawn pixel by pixel each frame.
void drawSprite128(
  Canvas canvas,
  Path shape, {
  required PixelFxPalette palette,
  required Offset light,
  required double reach,
  List<Path> holes = const [],
  Color holeColor = const Color(0xFF1A0508),
  int halo = 8,
  double fade = 1,
}) {
  if (fade <= 0) return;
  final box = shape.getBounds().inflate(halo * 2 + 2.0);
  final mask = PixelMask(box.left.floor(), box.top.floor(), box.width.ceil(), box.height.ceil());
  if (mask.cols <= 0 || mask.rows <= 0) return;
  final within = shape.getBounds();
  for (var y = 0; y < mask.rows; y++) {
    final py = mask.top + y + .5;
    if (py < within.top || py > within.bottom) continue;
    for (var x = 0; x < mask.cols; x++) {
      final p = Offset(mask.left + x + .5, py);
      if (shape.contains(p)) mask.set(x, y, holes.any((h) => h.contains(p)) ? PixelMask.hole : PixelMask.inside);
    }
  }
  paintSprite128(
    canvas,
    mask,
    palette: palette,
    light: light,
    reach: reach,
    holeColor: holeColor,
    halo: halo,
    fade: fade,
  );
}

/// A shape on a grid of screen pixels from ([left], [top]): each cell
/// outside (0), [inside] or in a [hole].
class PixelMask {
  PixelMask(this.left, this.top, this.cols, this.rows) : _cells = Uint8List(math.max(0, cols * rows));

  final int left, top, cols, rows;
  final Uint8List _cells;

  static const inside = 1, hole = 2;

  int at(int x, int y) => _cells[y * cols + x];
  void set(int x, int y, int value) => _cells[y * cols + x] = value;

  /// In the shape (a hole too); false off the grid.
  bool isIn(int x, int y) => x >= 0 && y >= 0 && x < cols && y < rows && _cells[y * cols + x] != 0;
}

/// The brightest shade of a 128-bit sprite: its palette's first, toward white.
Color sprite128Heart(PixelFxPalette palette) => Color.lerp(palette.levels.first, const Color(0xFFFFFFFF), .45)!;

/// Paints [mask] the 128-bit way (see [drawSprite128]).
void paintSprite128(
  Canvas canvas,
  PixelMask mask, {
  required PixelFxPalette palette,
  required Offset light,
  required double reach,
  Color holeColor = const Color(0xFF1A0508),
  int halo = 8,
  double fade = 1,
}) {
  const big = 2;
  final left = mask.left, top = mask.top, cols = mask.cols, rows = mask.rows;
  final isIn = mask.isIn;
  final paint = Paint()..isAntiAlias = false;

  // The halo, on a grid of 2, in steps.
  if (halo > 0) {
    final bc = (cols / big).ceil(), br = (rows / big).ceil();
    final dist = Uint8List(bc * br), seen = Uint8List(bc * br);
    var ring = <(int, int)>[];
    for (var y = 0; y < br; y++) {
      for (var x = 0; x < bc; x++) {
        if (isIn(x * big, y * big) || isIn(x * big + 1, y * big + 1)) {
          seen[y * bc + x] = 1;
          ring.add((x, y));
        }
      }
    }
    for (var d = 1; d <= halo; d++) {
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
    for (var y = 0; y < br; y++) {
      for (var x = 0; x < bc; x++) {
        final d = dist[y * bc + x];
        if (d == 0) continue;
        final k = 1 - (d - 1) / halo;
        if (_dither(x, y) > k * 1.15 || _dither(x + 1, y + 2) > fade) continue;
        paint.color = Color.lerp(palette.levels[1], palette.levels.first, k * .5)!.withValues(alpha: .25 + .4 * k);
        canvas.drawRect(
          Rect.fromLTWH((left + x * big).toDouble(), (top + y * big).toDouble(), big.toDouble(), big.toDouble()),
          paint,
        );
      }
    }
  }

  // The shape, shaded and dithered, its edge lit.
  final heart = sprite128Heart(palette);
  final ramp = [heart, ...palette.levels];
  Color shade(double t) {
    final f = t.clamp(0.0, 1.0) * (ramp.length - 1);
    final i = math.min(f.floor(), ramp.length - 2);
    return Color.lerp(ramp[i], ramp[i + 1], f - i)!;
  }

  const levels = 16;
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      final v = mask.at(x, y);
      if (v == 0 || _dither(x >> 1, (y >> 1) + 1) > fade) continue;
      final rect = Rect.fromLTWH((left + x).toDouble(), (top + y).toDouble(), 1, 1);
      if (v == PixelMask.hole) {
        paint.color = holeColor;
        canvas.drawRect(rect, paint);
        continue;
      }
      final t = ((Offset(left + x + .5, top + y + .5) - light).distance / reach).clamp(0.0, 1.0);
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
      canvas.drawRect(rect, paint);
    }
  }
}

/// 4 × 4 ordered dither, 0 to 1.
const _bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
double _dither(int x, int y) => (_bayer[(y % 4) * 4 + x % 4] + .5) / 16;
