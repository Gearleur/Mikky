import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../ui/pixel_fx.dart';
import '../ui/tokens.dart';

/// Waves of dots on a small grid (2026-10-06, after the user's frames of a
/// « vague de réflexion »: a little cluster opens into an oval ring of
/// dots that grows past the edges and fades): ours in our blue, and other
/// shapes. Each is a function of time on a grid; a dot lit by how close it
/// is to the shape, in the four steps of the palette.
enum DotWave {
  ripple('Onde', 'La vague de réflexion : un petit groupe au centre s’ouvre en anneau ovale, grandit au-delà des bords et s’éteint ; une autre suit.', 1600),
  pulse('Pouls', 'Un cœur qui bat au centre, et à chaque battement un anneau part.', 1400),
  sine('Vague', 'Une ligne de points qui ondule de gauche à droite, plus haute au milieu : une voix.', 1600),
  spiral('Spirale', 'Deux bras de points qui tournent en s’enroulant depuis le centre.', 2400),
  diamond('Losange', 'L’onde en losange : la même vague, en marches.', 1600),
  square('Carré', 'L’onde en carré arrondi, comme l’île.', 1600),
  radar('Radar', 'Un rayon qui balaie le cercle et laisse une traîne qui s’éteint.', 2000),
  equalizer('Égaliseur', 'Des colonnes de points qui montent et descendent, chacune à son rythme.', 1600);

  const DotWave(this.label, this.note, this.periodMs);

  final String label, note;
  final int periodMs;

  Duration get period => Duration(milliseconds: periodMs);
}

/// One [wave] at [t] seconds, on the island's background.
class DotWaveScene extends StatelessWidget {
  const DotWaveScene(this.wave, this.t, {super.key, this.palette = PixelFxPalette.signatureBlue, this.cols = 30, this.rows = 18, this.step = 5.0});

  final DotWave wave;
  final double t;
  final PixelFxPalette palette;
  final int cols, rows;

  /// Between two dots; a dot is half of it.
  final double step;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: cols * step + 16,
      height: rows * step + 16,
      color: ui.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708),
      padding: const EdgeInsets.all(8),
      child: CustomPaint(painter: _DotWavePainter(wave, t, palette, cols, rows, step, ui.isLight)),
    );
  }
}

class _DotWavePainter extends CustomPainter {
  _DotWavePainter(this.wave, this.t, this.palette, this.cols, this.rows, this.step, this.light);

  final DotWave wave;
  final double t;
  final PixelFxPalette palette;
  final int cols, rows;
  final double step;
  final bool light;

  /// Rows count more than columns: the shapes are wider than high, as in
  /// the user's frames.
  static const _tall = 1.6;

  static double _ring(double d, double r, double width) => math.exp(-math.pow((d - r) / width, 2));

  /// How lit the dot at ([dx], [dy]) from the middle is (0 to 1), at the
  /// point [u] (0 to 1) of the loop.
  double _at(double dx, double dy, double u) {
    final half = cols / 2;
    switch (wave) {
      case DotWave.ripple || DotWave.diamond || DotWave.square:
        final d = switch (wave) {
          DotWave.diamond => dx.abs() + (dy * _tall).abs(),
          DotWave.square => math.pow(math.pow(dx.abs(), 4) + math.pow((dy * _tall).abs(), 4), .25).toDouble(),
          _ => math.sqrt(dx * dx + dy * dy * _tall * _tall),
        };
        // One wave at a time, as in the user's frames: the cluster, the
        // ring opening, its arcs past the edges, fading.
        final r = u * half * 1.3;
        final core = d < 1.6 ? math.max(0.0, 1 - u * 5) : 0.0;
        return math.max(core, _ring(d, r, .72) * math.pow(1 - u, .8));
      case DotWave.pulse:
        final d = math.sqrt(dx * dx + dy * dy * _tall * _tall);
        final beat = math.pow(math.max(0.0, math.cos(u * math.pi * 2)), 6).toDouble();
        final heart = d < 2.4 + beat * 1.4 ? .55 + .45 * beat : 0.0;
        final r = 2 + u * half;
        return math.max(heart, _ring(d, r, .65) * math.pow(1 - u, 1.4));
      case DotWave.sine:
        final x = dx / half;
        final envelope = math.exp(-x * x * 2.2);
        final y = math.sin(dx * .45 - u * math.pi * 2) * rows * .36 * envelope;
        final second = math.sin(dx * .3 + u * math.pi * 2 + 1) * rows * .2 * envelope;
        return math.max(_ring(dy, y, .7), _ring(dy, second, .6) * .55);
      case DotWave.spiral:
        final d = math.sqrt(dx * dx + dy * dy * _tall * _tall);
        if (d > half) return 0;
        final angle = math.atan2(dy * _tall, dx);
        var lit = 0.0;
        for (final arm in const [0.0, math.pi]) {
          var diff = (angle - (d * .32 - u * math.pi * 2 + arm)) % (math.pi * 2);
          if (diff > math.pi) diff -= math.pi * 2;
          lit = math.max(lit, math.exp(-math.pow(diff / .35, 2)));
        }
        return lit * (1 - d / half) * 1.3;
      case DotWave.radar:
        final d = math.sqrt(dx * dx + dy * dy * _tall * _tall);
        final reach = rows / 2 * _tall;
        if (d > reach) return 0;
        final angle = math.atan2(dy * _tall, dx);
        final behind = (u * math.pi * 2 - angle) % (math.pi * 2);
        final trail = math.exp(-behind / .45);
        final edge = _ring(d, reach - .5, .6) * .35;
        return math.max(edge, trail * (.35 + .65 * d / reach));
      case DotWave.equalizer:
        // A bar every third column.
        final column = (dx / 3).round();
        if ((dx - column * 3).abs() > .5) return 0;
        final seed = column * 1.7;
        final h = rows * .42 * (.15 + .85 * math.pow(math.sin(u * math.pi * 2 * (1 + (column % 3)) + seed).abs(), 1.4) * math.exp(-math.pow(column / (half / 2), 2) * .6));
        if (dy.abs() > h) return 0;
        return .45 + .55 * (1 - dy.abs() / math.max(h, .5));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final u = (t * 1000 / wave.periodMs) % 1;
    final paint = Paint()..isAntiAlias = false;
    final faint = Paint()
      ..isAntiAlias = false
      ..color = (light ? const Color(0xFF000000) : const Color(0xFFFFFFFF)).withValues(alpha: light ? .05 : .06);
    final dot = (step / 2).roundToDouble();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final rect = Rect.fromLTWH(x * step, y * step, dot, dot);
        // Brighter than linear: the shapes read in the light blues.
        final level = pixelLevel(math.pow(_at(x - (cols - 1) / 2, y - (rows - 1) / 2, u).clamp(0.0, 1.0), .65).toDouble());
        if (level == null) {
          // The grid, barely there.
          canvas.drawRect(rect, faint);
          continue;
        }
        paint.color = palette.levels[level];
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotWavePainter old) => old.t != t || old.wave != wave || old.palette != palette || old.light != light;
}
