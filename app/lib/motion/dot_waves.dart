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
  ripple(
    'Onde',
    'La vague de réflexion : un petit groupe au centre s’ouvre en anneau ovale, grandit au-delà des bords et s’éteint ; une autre suit.',
    1600,
  ),
  pulse('Pouls', 'Un cœur qui bat au centre, et à chaque battement un anneau part.', 1400),
  sine('Vague', 'Une ligne de points qui ondule de gauche à droite, plus haute au milieu : une voix.', 1600),
  spiral('Spirale', 'Deux bras de points qui tournent en s’enroulant depuis le centre.', 2400),
  diamond('Losange', 'L’onde en losange : la même vague, en marches.', 1600),
  square('Carré', 'L’onde en carré arrondi, comme l’île.', 1600),
  radar('Radar', 'Un rayon qui balaie le cercle et laisse une traîne qui s’éteint.', 2000),
  equalizer('Égaliseur', 'Des colonnes de points qui montent et descendent, chacune à son rythme.', 1600),
  spiralFade(
    'Spirale qui s’efface',
    'Un bras qui se dessine en tournant depuis le centre, sa tête vive, et s’efface derrière elle.',
    2600,
  ),
  orbit('Orbite', 'Une comète qui tourne sur l’ovale, sa traîne en dégradé.', 1800),
  drops('Gouttes', 'Des gouttes qui tombent ici et là, chacune ouvre son petit cercle.', 2400),
  breath('Respiration', 'Un disque en dégradé qui grandit et rapetisse, comme un souffle.', 2800),
  vortex('Tourbillon', 'Des anneaux en pointillés qui tournent en sens contraires.', 3000),
  infinity('Infini', 'Un point qui dessine un huit couché, sa traîne en dégradé derrière lui.', 2400),
  scanner('Scanner', 'Une barre qui monte et descend, sa traîne qui s’éteint derrière.', 1800),
  star('Étoile', 'Une étoile à quatre branches qui s’allume et s’éteint, ses rayons en dégradé.', 1600),

  // Maths and magic (2026-10-06, « des choses mathématiques, des choses
  // magiques, dans la DA de notre app »): fields and curves that fill the
  // grid, on a wider gradient, from night blue to white.
  lissajous(
    'Lissajous',
    'Une courbe de Lissajous (3 : 2) parcourue par un point, sa traîne en dégradé.',
    3200,
    magic: true,
  ),
  rose(
    'Rosace',
    'Une rose à trois pétales (r = cos 3θ) qui tourne lentement, plus vive au bout des pétales.',
    3000,
    magic: true,
  ),
  interference(
    'Interférences',
    'Deux sources d’ondes qui se croisent : leurs franges vont et viennent sur toute la grille.',
    2200,
    magic: true,
  ),
  plasma(
    'Plasma',
    'Une somme de sinus qui coule sur toute la grille, comme les démos des vieux ordinateurs.',
    4000,
    magic: true,
  ),
  goldenSpiral(
    'Spirale d’or',
    'Une spirale logarithmique (celle du nombre d’or) parcourue depuis le cœur, sa traîne en dégradé.',
    2600,
    magic: true,
  ),
  magicCircle(
    'Cercle magique',
    'Deux cercles, un hexagramme qui tourne, des runes qui tournent en sens inverse.',
    6000,
    magic: true,
  ),
  chladni(
    'Chladni',
    'Les lignes de sable d’une plaque qui vibre : elles se déforment d’un motif à l’autre.',
    4000,
    magic: true,
  ),
  codeRain('Pluie de code', 'Des colonnes de points qui tombent, leur tête vive : du calcul.', 2000, magic: true),
  kaleidoscope('Kaléidoscope', 'Un motif à huit branches symétriques qui pulse depuis le centre.', 3000, magic: true),
  aurora('Aurore', 'Un ruban de lumière qui ondule, strié comme une aurore.', 4000, magic: true);

  const DotWave(this.label, this.note, this.periodMs, {this.magic = false});

  final String label, note;
  final int periodMs;

  /// One of the maths and magic ones, on the wide gradient.
  final bool magic;

  Duration get period => Duration(milliseconds: periodMs);
}

/// One [wave] at [t] seconds, on the island's background.
class DotWaveScene extends StatelessWidget {
  const DotWaveScene(
    this.wave,
    this.t, {
    super.key,
    this.palette = PixelFxPalette.signatureBlue,
    this.cols = 30,
    this.rows = 18,
    this.step = 5.0,
  });

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

  static double _hash(int i) => pixelHash(i * 7919 + 13);

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
        final h =
            rows *
            .42 *
            (.15 +
                .85 *
                    math.pow(math.sin(u * math.pi * 2 * (1 + (column % 3)) + seed).abs(), 1.4) *
                    math.exp(-math.pow(column / (half / 2), 2) * .6));
        if (dy.abs() > h) return 0;
        return .45 + .55 * (1 - dy.abs() / math.max(h, .5));
      case DotWave.spiralFade:
        final d = math.sqrt(dx * dx + dy * dy * _tall * _tall);
        // Its head runs out from the center; its tail follows and erases.
        final head = u * half * 1.7, tail = head - half * .9;
        if (d > head || d < tail) return 0;
        final angle = math.atan2(dy * _tall, dx);
        var diff = (angle - (d * .62 - u * math.pi * 1.2)) % (math.pi * 2);
        if (diff > math.pi) diff -= math.pi * 2;
        final along = (d - math.max(tail, 0)) / math.max(head - math.max(tail, 0), .1);
        return math.exp(-math.pow(diff / .5, 2)) * math.pow(along, 1.3);
      case DotWave.orbit:
        final rx = half * .78, ry = rows / 2 * .78;
        final e = math.sqrt(math.pow(dx / rx, 2) + math.pow(dy / ry, 2));
        final near = math.exp(-math.pow((e - 1) / .1, 2));
        if (near < .05) return 0;
        final angle = math.atan2(dy / ry, dx / rx);
        final behind = (u * math.pi * 2 - angle) % (math.pi * 2);
        return near * math.exp(-behind / 1.4);
      case DotWave.drops:
        var lit = 0.0;
        for (var k = 0; k < 6; k++) {
          // Each drop at its own place and moment, again and again.
          final p = (u + k / 6) % 1;
          final cx = (_hash(k * 3 + 1) - .5) * cols * .8, cy = (_hash(k * 3 + 2) - .5) * rows * .7;
          final d = math.sqrt(math.pow(dx - cx, 2) + math.pow((dy - cy) * _tall, 2));
          final r = p * 6;
          final splash = d < 1 ? math.max(0.0, 1 - p * 6) : 0.0;
          lit = math.max(lit, math.max(splash, _ring(d, r, .6) * math.pow(1 - p, 1.2)));
        }
        return lit;
      case DotWave.breath:
        final d = math.sqrt(dx * dx + dy * dy * _tall * _tall);
        final r = 3 + 9 * (.5 - .5 * math.cos(u * math.pi * 2));
        return math.pow((1 - d / r).clamp(0.0, 1.0), .8).toDouble();
      case DotWave.vortex:
        final d = math.sqrt(dx * dx + dy * dy * _tall * _tall);
        final angle = math.atan2(dy * _tall, dx);
        var lit = 0.0;
        for (var k = 1; k <= 3; k++) {
          final turn = (k.isEven ? 1 : -1) * u * math.pi * 2;
          // A few long dashes per ring, soft at their ends.
          final dash = math.pow(.5 + .5 * math.sin(angle * k + turn), 2).toDouble();
          lit = math.max(lit, _ring(d, k * 5.0, .65) * dash * (1.2 - k * .15));
        }
        return lit;
      case DotWave.infinity:
        // The figure eight, sampled; how far behind the head each dot is.
        const n = 120;
        final a = half * .85;
        var best = 1e9, at = 0;
        for (var i = 0; i < n; i++) {
          final q = i / n * math.pi * 2, den = 1 + math.pow(math.sin(q), 2);
          final px = a * math.cos(q) / den, py = a * math.sin(q) * math.cos(q) / den / _tall * 1.6;
          final dd = math.pow(dx - px, 2) + math.pow((dy - py) * _tall, 2);
          if (dd < best) {
            best = dd.toDouble();
            at = i;
          }
        }
        if (best > 1.1) return 0;
        final behind = ((u * n).floor() - at) % n;
        return math.exp(-behind / 26) * math.exp(-best / .7);
      case DotWave.scanner:
        final y = math.sin(u * math.pi * 2) * rows / 2 * .82;
        final going = math.cos(u * math.pi * 2);
        final behind = (y - dy) * going.sign;
        return behind > 0 ? math.exp(-behind / 2.6) * .85 : math.exp(-math.pow(behind / .5, 2));
      case DotWave.star:
        final pulse = .5 - .5 * math.cos(u * math.pi * 2);
        final reach = 2 + 12 * pulse;
        final ax = dx.abs(), ay = (dy * _tall).abs();
        final straight = ay < .7 ? 1 - ax / reach : (ax < .7 ? 1 - ay / reach : 0.0);
        final diagonal = (ax - ay).abs() < .8 ? 1 - (ax + ay) / (reach * .9) : 0.0;
        final core = math.sqrt(ax * ax + ay * ay) < 1.6 ? .6 + .4 * pulse : 0.0;
        return math.max(core, math.max(straight, diagonal * .7).clamp(0.0, 1.0) * (.4 + .6 * pulse));
      case DotWave.lissajous:
        // x = sin(3s + ½), y = sin(2s): a point runs on it, its trail fades.
        return _trail(dx, dy, u, (s) => (half * .85 * math.sin(3 * s + .5), rows / 2 * .8 * math.sin(2 * s)), 26);
      case DotWave.rose:
        final d = math.sqrt(dx * dx + dy * dy * _tall * _tall);
        final angle = math.atan2(dy * _tall, dx);
        // A third of a turn per loop: the same rose again.
        final petal = math.cos(3 * (angle - u * math.pi * 2 / 3)).abs();
        final r = rows / 2 * _tall * .92 * petal;
        return _ring(d, r, .8) * (.35 + .65 * petal) + (d < 1.2 ? .5 : 0);
      case DotWave.interference:
        final d1 = math.sqrt(math.pow(dx + half * .45, 2) + math.pow(dy * _tall, 2));
        final d2 = math.sqrt(math.pow(dx - half * .45, 2) + math.pow(dy * _tall, 2));
        final w = u * math.pi * 2;
        final v = .5 + .25 * (math.cos(d1 * 1.05 - w) + math.cos(d2 * 1.05 - w));
        return math.pow(v, 2.2).toDouble();
      case DotWave.plasma:
        final w = u * math.pi * 2;
        final v =
            math.sin(dx * .32 + w) +
            math.sin(dy * .55 - w) +
            math.sin((dx + dy) * .22 + w) +
            math.sin(math.sqrt(dx * dx + dy * dy * 2.5) * .42 - w);
        return math.pow((v + 4) / 8, 1.6).toDouble();
      case DotWave.goldenSpiral:
        // r = a·e^(bθ) over two turns, run from the heart outward.
        return _trail(dx, dy, u, (s) {
          final theta = s * 2;
          final r = .55 * math.exp(.235 * theta);
          return (r * math.cos(theta), r * math.sin(theta) / _tall);
        }, 70);
      case DotWave.magicCircle:
        final d = math.sqrt(dx * dx + dy * dy * _tall * _tall);
        final angle = math.atan2(dy * _tall, dx);
        final outer = rows / 2 * _tall * .95, inner = outer * .72;
        var lit = math.max(_ring(d, outer, .55) * .6, _ring(d, inner, .5) * .45);
        // The hexagram: two triangles on the inner circle, a sixth of a
        // turn per loop.
        final turn = u * math.pi * 2 / 6;
        for (var k = 0; k < 6; k++) {
          final a0 = turn + k * math.pi / 3, a1 = a0 + math.pi * 2 / 3;
          final p0 = (inner * math.cos(a0), inner * math.sin(a0)), p1 = (inner * math.cos(a1), inner * math.sin(a1));
          final line = _segment(dx, dy * _tall, p0, p1);
          // A light runs along each line.
          final glow = .55 + .45 * math.cos(u * math.pi * 2 * 2 + k);
          lit = math.max(lit, math.exp(-math.pow(line / .5, 2)) * glow);
        }
        // Runes on the outer ring, turning the other way.
        for (var k = 0; k < 12; k++) {
          final a = -u * math.pi * 2 / 12 + k * math.pi / 6;
          var diff = (angle - a) % (math.pi * 2);
          if (diff > math.pi) diff -= math.pi * 2;
          if (diff.abs() < .09 && (d - outer - 1.6).abs() < .9) lit = math.max(lit, k.isEven ? 1.0 : .6);
        }
        return lit;
      case DotWave.chladni:
        final x = dx / half, y = dy / (rows / 2);
        final a = .5 - .5 * math.cos(u * math.pi * 2);
        // Never the same two frequencies: the plate would be all lines.
        final n = 1 + .8 * a, m = 3.2 - .8 * a;
        final f =
            math.cos(n * math.pi * x) * math.cos(m * math.pi * y) -
            math.cos(m * math.pi * x) * math.cos(n * math.pi * y);
        return math.exp(-math.pow(f / .32, 2));
      case DotWave.codeRain:
        final column = (dx / 2).round();
        if ((dx - column * 2).abs() > .5) return 0;
        final speed = 1 + (_hash(column + 40) * 2).floor();
        final length = 4 + _hash(column + 80) * 7;
        final head = ((u * speed + _hash(column + 20)) % 1) * (rows + length) - rows / 2;
        final behind = head - dy;
        if (behind < 0 || behind > length) return 0;
        // The cells flicker a little, like changing characters.
        final flicker = .75 + .25 * _hash((dy * 7 + column * 31 + (u * 12).floor() * 13).round());
        return (behind < .6 ? 1.0 : math.pow(1 - behind / length, 1.4) * .85) * flicker;
      case DotWave.kaleidoscope:
        final d = math.sqrt(dx * dx + dy * dy * _tall * _tall);
        final angle = math.atan2(dy * _tall, dx);
        // Eight mirrored slices.
        const slice = math.pi / 4;
        final folded = ((angle + u * slice) % slice - slice / 2).abs();
        final v = math.cos(d * .55 - u * math.pi * 2) * math.cos(folded * 5 + d * .2);
        final fade = (1 - d / (half * 1.1)).clamp(0.0, 1.0);
        return math.pow((v + 1) / 2, 1.8) * fade * 1.2;
      case DotWave.aurora:
        final w = u * math.pi * 2;
        final y0 = math.sin(dx * .17 + w) * 3 + math.sin(dx * .07 - w) * 2;
        final band = math.exp(-math.pow((dy - y0) / 3.2, 2));
        final rays = .45 + .55 * math.pow(.5 + .5 * math.sin(dx * .55 + w * 2), 2);
        return band * rays;
    }
  }

  /// A point running on [curve] (its parameter 0 to 2π, one turn per
  /// loop), and how lit the dot at ([dx], [dy]) is from its trail.
  double _trail(double dx, double dy, double u, (double, double) Function(double s) curve, double length) {
    const n = 160;
    var best = 1e9, at = 0;
    for (var i = 0; i < n; i++) {
      final (px, py) = curve(i / n * math.pi * 2);
      final dd = math.pow(dx - px, 2) + math.pow((dy - py) * _tall, 2);
      if (dd < best) {
        best = dd.toDouble();
        at = i;
      }
    }
    if (best > 1.2) return 0;
    final behind = ((u * n).floor() - at) % n;
    return math.exp(-behind / length) * math.exp(-best / .8);
  }

  /// Distance from ([x], [y]) to the segment [a]–[b].
  static double _segment(double x, double y, (double, double) a, (double, double) b) {
    final (ax, ay) = a;
    final (bx, by) = b;
    final vx = bx - ax, vy = by - ay;
    final t = (((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)).clamp(0.0, 1.0);
    return math.sqrt(math.pow(x - ax - vx * t, 2) + math.pow(y - ay - vy * t, 2));
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
        final lit = _at(x - (cols - 1) / 2, y - (rows - 1) / 2, u).clamp(0.0, 1.0);
        if (lit < (wave.magic ? .03 : .06)) {
          // The grid, barely there.
          canvas.drawRect(rect, faint);
          continue;
        }
        // A continuous gradient (« plus de gradient, plus voyant »): from
        // almost white where it is brightest, through the palette, to its
        // deepest blue fading out.
        paint.color = wave.magic ? _deep(math.pow(lit, .85).toDouble()) : _shade(math.pow(lit, .7).toDouble());
        canvas.drawRect(rect, paint);
      }
    }
  }

  /// The wide gradient of the maths and magic ones (« plus étalé, plus
  /// sombres et plus clairs »): night blue, deep blue, our blues, cyan,
  /// white; the dark end stays visible instead of fading out.
  static const _night = [
    Color(0xFF0A0F3D),
    Color(0xFF0B1E8F),
    Color(0xFF0045E5),
    Color(0xFF0F84FA),
    Color(0xFF04BCFF),
    Color(0xFF8CE8FF),
    Color(0xFFFFFFFF),
  ];

  Color _deep(double i) {
    final f = i * (_night.length - 1);
    final k = math.min(f.floor(), _night.length - 2);
    return Color.lerp(_night[k], _night[k + 1], f - k)!.withValues(alpha: (i * 5).clamp(.4, 1.0));
  }

  Color _shade(double i) {
    final ramp = [
      palette.levels[3],
      palette.levels[2],
      palette.levels[1],
      palette.levels[0],
      Color.lerp(palette.levels[0], const Color(0xFFFFFFFF), .7)!,
    ];
    final f = i * (ramp.length - 1);
    final k = math.min(f.floor(), ramp.length - 2);
    final color = Color.lerp(ramp[k], ramp[k + 1], f - k)!;
    return color.withValues(alpha: (i * 2.2).clamp(.25, 1.0));
  }

  @override
  bool shouldRepaint(_DotWavePainter old) =>
      old.t != t || old.wave != wave || old.palette != palette || old.light != light;
}
