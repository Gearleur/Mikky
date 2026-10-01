import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// Trials, shown on the design boards only: pictures drawn pixel by pixel
// (Mikky in pixels, to try as the logo; design.md §12, « plus tard »).

/// A small picture drawn pixel by pixel from a map: one character per
/// pixel, [colors] gives each one's color, « . » and unknown ones are
/// empty.
class PixelMap extends StatelessWidget {
  const PixelMap(this.rows, {super.key, required this.colors, this.size = 64, this.outline, this.gap = 0});

  final List<String> rows;
  final Map<String, Color> colors;
  final double size;

  /// Drawn on the empty pixels touching the picture: to separate a black
  /// picture from a dark background.
  final Color? outline;

  /// Space between pixels, against the size (the fireworks: .018); none
  /// for a solid picture.
  final double gap;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: PixelMapPainter(rows, colors, outline, gap));
}

/// Mikky in pixels (user request, 2026-09-30, to try as the logo): his
/// head, the two ears up, the big white eyes, nothing else.
abstract final class PixelMikky {
  static const head = [
    '................',
    '.kk..........kk.',
    '.kkk........kkk.',
    '.kkkk......kkkk.',
    '.kkkkkkkkkkkkkk.',
    'kkkkkkkkkkkkkkkk',
    'kkkwwkkkkkkwwkkk',
    'kkkwwkkkkkkwwkkk',
    'kkkwwkkkkkkwwkkk',
    'kkkkkkkkkkkkkkkk',
    '.kkkkkkkkkkkkkk.',
    '..kkkkkkkkkkkk..',
    '....kkkkkkkk....',
    '................',
    '................',
    '................',
  ];

  static const colors = {'k': Color(0xFF0C0C0E), 'w': Color(0xFFF7F7F7)};
}

class PixelMapPainter extends CustomPainter {
  PixelMapPainter(this.rows, this.colors, [this.outline, this.gapRatio = .018]);

  final List<String> rows;
  final Map<String, Color> colors;
  final Color? outline;
  final double gapRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final n = math.max(rows.length, rows.fold(0, (a, r) => math.max(a, r.length)));
    final side = size.shortestSide;
    final gap = side * gapRatio;
    final cell = (side - gap * (n - 1)) / n;
    // Centered: the rows used, in the middle of the square.
    final used = [for (var y = 0; y < rows.length; y++) if (rows[y].split('').any(colors.containsKey)) y];
    final dy = used.isEmpty ? 0.0 : ((n - 1 - used.last) - used.first) / 2 * (cell + gap);
    bool filled(int x, int y) => y >= 0 && y < rows.length && x >= 0 && x < rows[y].length && colors.containsKey(rows[y][x]);
    // Solid pictures: no smoothing, or thin seams show between pixels.
    final paint = Paint()..isAntiAlias = gap > 0;
    for (var y = -1; y <= rows.length; y++) {
      for (var x = -1; x <= n; x++) {
        Color? color;
        if (filled(x, y)) {
          color = colors[rows[y][x]];
        } else if (outline != null && (filled(x - 1, y) || filled(x + 1, y) || filled(x, y - 1) || filled(x, y + 1))) {
          color = outline;
        }
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(Rect.fromLTWH(x * (cell + gap), dy + y * (cell + gap), cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(PixelMapPainter old) => old.rows != rows || old.outline != outline;
}
