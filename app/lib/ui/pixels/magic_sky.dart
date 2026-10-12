import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../foundation/motion.dart';
import 'pixel_fx.dart';

/// Mikky's sky (2026-10-12, from an image of the user: « un ciel étoilé
/// avec un tout petit peu de nuage dans le même style, des étoiles
/// filantes, nos couleurs bleu et orange »; still clouds, glitched, a
/// white version): a few clouds of dots on a grid, dithered — dense at
/// their top, scattered at their foot — and glitched: slices shifted
/// sideways, holes, their edge doubled in our blue on the left and our
/// orange on the right; fine stars, some blue or orange. Only stars
/// twinkle, and now and then a shooting star crosses, a trail of pixels
/// in our blue, then our orange.
///
/// Cheap: the sky, its clouds and its still stars are painted once; only
/// a thin layer moves — a few dozen squares — at 15 images a second on
/// the [DecorClock], and not at all when hidden or when Windows asks for
/// fewer animations.
class MagicSky extends StatefulWidget {
  const MagicSky({super.key, this.light = false, this.clouds = MagicSky.someClouds, this.seed = 7, this.at});

  /// The white version.
  final bool light;

  /// Where the clouds are: their center and width, as parts of the sky.
  final List<({double x, double y, double width})> clouds;
  final int seed;

  /// Shows that moment (seconds), still (the boards' pictures).
  final double? at;

  /// A big one up on the right, two small ones low (« un tout petit peu
  /// de nuage »).
  static const someClouds = [(x: .64, y: .26, width: .5), (x: .17, y: .78, width: .3), (x: .92, y: .9, width: .24)];

  @override
  State<MagicSky> createState() => _MagicSkyState();
}

class _MagicSkyState extends State<MagicSky> with DecorTicks {
  @override
  double? get decorStill => widget.at;

  _Sky? _sky;

  @override
  void dispose() {
    _sky?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final look = widget.light ? _Look.day : _Look.night;
        var sky = _sky;
        if (sky == null ||
            sky.size != size ||
            sky.seed != widget.seed ||
            sky.look != look ||
            !identical(sky.layout, widget.clouds)) {
          sky?.dispose();
          sky = _sky = _Sky(size, widget.clouds, widget.seed, look);
        }
        // The clouds may reach past the edge: the stack cuts them there.
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: CustomPaint(painter: _StillPainter(sky))),
            RepaintBoundary(child: CustomPaint(painter: _LivePainter(sky, decorTime))),
          ],
        );
      },
    ),
  );
}

/// The colours of a version: its sky, its clouds' dots, its white stars.
class _Look {
  const _Look({required this.sky, required this.cloud, required this.star, required this.cloudAlpha});

  final Color sky, cloud, star;

  /// The clouds' dots, from their top to their foot.
  final (double, double) cloudAlpha;

  static const night = _Look(
    sky: Color(0xFF04050A),
    cloud: Color(0xFFA0A0A8),
    star: Color(0xFFFFFFFF),
    cloudAlpha: (.85, .35),
  );
  static const day = _Look(
    sky: Color(0xFFFFFFFF),
    cloud: Color(0xFF6E6E73),
    star: Color(0xFF8E8E93),
    cloudAlpha: (.75, .3),
  );
}

/// A star: where, how big (1 or 2 px), its colour, and whether it
/// twinkles (then it is drawn by the moving layer, not the still one).
typedef _Star = ({Offset at, double size, Color color, bool twinkles, double phase});

/// Everything laid out once for a size.
class _Sky {
  _Sky(this.size, this.layout, this.seed, this.look) {
    final rng = math.Random(seed);
    final count = (size.width * size.height / 2600).round();
    for (var i = 0; i < count; i++) {
      final roll = rng.nextDouble();
      final colour = roll < .06
          ? _blue
          : roll < .11
          ? _orange
          : look.star.withValues(alpha: .25 + .6 * rng.nextDouble() * rng.nextDouble());
      stars.add((
        at: Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height).snap,
        size: rng.nextDouble() < .12 ? 2 : 1,
        color: colour,
        twinkles: rng.nextDouble() < .16,
        phase: rng.nextDouble() * math.pi * 2,
      ));
    }
    for (final c in layout) {
      final image = _cloudImage(c.width * size.width, rng, look);
      clouds.add((
        image: image,
        at: Offset(c.x * size.width - image.width / 2, c.y * size.height - image.height / 2).snap,
      ));
    }
  }

  final Size size;
  final List<({double x, double y, double width})> layout;
  final int seed;
  final _Look look;
  final stars = <_Star>[];
  final clouds = <({ui.Image image, Offset at})>[];

  static const _blue = Color(0xFF3FD8FF), _orange = Color(0xFFFFB020);

  /// A cloud's dots: every [step] px, [dot] px wide; room on its sides for
  /// its shifted slices and its doubled edge.
  static const step = 3.0, dot = 2.0, _margin = 14;

  void dispose() {
    for (final c in clouds) {
      c.image.dispose();
    }
  }

  /// One cloud, [width] wide: a cumulus — a row of small puffs for its
  /// body, bigger ones piled on it — its dots kept by an ordered dither
  /// from a density (full at its top, thinner to its foot and its edges,
  /// ragged; sparse rows under it). Then glitched: some slices of rows
  /// shifted sideways, a few holes, its edge doubled in blue on the left
  /// and orange on the right, a few brighter blocks.
  static ui.Image _cloudImage(double width, math.Random rng, _Look look) {
    final w = width, h = width * .52;
    double rand(double a, double b) => a + (b - a) * rng.nextDouble();
    final puffs = <({Offset c, double r})>[
      for (var i = 0; i < 7; i++)
        (c: Offset(w * (.1 + .8 * i / 6 + rand(-.03, .03)), h * rand(.6, .68)), r: w * rand(.07, .11)),
      for (var i = 0; i < 4; i++)
        (c: Offset(w * (.22 + .5 * i / 3 + rand(-.05, .05)), h * rand(.42, .52)), r: w * rand(.12, .17)),
      (c: Offset(w * rand(.48, .6), h * .33), r: w * rand(.16, .2)),
    ];
    final cols = (w / step).ceil(), rows = (h / step).ceil() + 7;
    final foot = [for (var c = 0; c < cols; c++) h * (.74 + rand(-.015, .015))];
    bool inside(double x, double y) {
      if (x < 0 || x >= w) return false;
      if (y > foot[(x / step).floor().clamp(0, cols - 1)]) return false;
      for (final p in puffs) {
        if ((Offset(x, y) - p.c).distanceSquared < p.r * p.r) return true;
      }
      return false;
    }

    final top = [
      for (var c = 0; c < cols; c++)
        () {
          final x = c * step + step / 2;
          for (var y = 0.0; y < h; y += step) {
            if (inside(x, y)) return y;
          }
          return h;
        }(),
    ];
    // The glitch: slices of 2 to 5 rows, a third of them shifted by one or
    // two dots; a few holes; a few brighter blocks.
    final shift = List.filled(rows, 0);
    for (var r = 0; r < rows;) {
      final n = 2 + rng.nextInt(4);
      final s = rng.nextDouble() < .42 ? (rng.nextBool() ? 1 : -1) * (1 + rng.nextInt(4)) : 0;
      for (var i = r; i < math.min(rows, r + n); i++) {
        shift[i] = s;
      }
      r += n;
    }
    final holes = [
      for (var i = 0; i < 4; i++)
        Rect.fromLTWH(rand(.1, .8) * w, rand(.25, .7) * h, rand(.08, .2) * w, step * (2 + rng.nextInt(3))),
    ];
    final bright = [for (var i = 0; i < 4; i++) Rect.fromLTWH(rand(.2, .75) * w, rand(.2, .5) * h, step * 3, step * 2)];

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = false;
    void put(int c, int r, Color colour) {
      paint.color = colour;
      canvas.drawRect(Rect.fromLTWH((c + shift[r] + _margin) * step, r * step, dot, dot), paint);
    }

    final (alphaTop, alphaFoot) = look.cloudAlpha;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = c * step + step / 2, y = r * step + step / 2;
        final height = ((y - top[c]) / (foot[c] - top[c] + 1)).clamp(0.0, 1.0);
        final noise = rand(-.12, .12);
        double density;
        var left = false, right = false;
        if (inside(x, y)) {
          left = !inside(x - step, y);
          right = !inside(x + step, y);
          final near = left || right || !inside(x, y - step);
          final far = !inside(x - step * 3, y) || !inside(x + step * 3, y) || !inside(x, y - step * 3);
          density = (1 - .62 * height) * (near ? .45 : (far ? .75 : 1)) + noise;
          if (holes.any((hole) => hole.contains(Offset(x, y)))) density *= .12;
          if (bright.any((b) => b.contains(Offset(x, y)))) density = 1;
        } else if (y > foot[c] && y < foot[c] + 7 * step && top[c] < h) {
          // Under it, sparse rows of dots, one row in two.
          density = r.isEven ? .28 * (1 - (y - foot[c]) / (7 * step)) + noise * .5 : 0;
        } else {
          continue;
        }
        // Its edge doubled, like colours slipping apart.
        if (left && rng.nextDouble() < .8) put(c - 2, r, _blue.withValues(alpha: .85));
        if (right && rng.nextDouble() < .8) put(c + 2, r, _orange.withValues(alpha: .85));
        if (density <= pixelDither(c, r)) continue;
        put(c, r, look.cloud.withValues(alpha: alphaTop + (alphaFoot - alphaTop) * height));
      }
    }
    // Two scan lines across it, running past its side.
    for (var i = 0; i < 2; i++) {
      final r = (rows * rand(.25, .65)).floor();
      final from = (cols * rand(-.25, .3)).floor(), to = (cols * rand(.7, 1.25)).ceil();
      for (var c = from; c < to; c += 2) {
        if (c + shift[r] + _margin < 0 || c + shift[r] >= cols + _margin) continue;
        final edge = c < 0 || c >= cols;
        put(c, r, (edge ? (c < 0 ? _blue : _orange) : look.cloud).withValues(alpha: edge ? .7 : .55));
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(((cols + 2 * _margin) * step).toInt(), (rows * step).toInt());
    picture.dispose();
    return image;
  }
}

extension on Offset {
  /// On whole pixels: the pixels stay sharp.
  Offset get snap => Offset(dx.roundToDouble(), dy.roundToDouble());
}

/// The sky, its clouds and the stars that do not twinkle, once.
class _StillPainter extends CustomPainter {
  _StillPainter(this.sky);

  final _Sky sky;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = sky.look.sky);
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    for (final s in sky.stars) {
      if (s.twinkles) continue;
      paint.color = s.color;
      canvas.drawRect(s.at & Size(s.size, s.size), paint);
    }
    for (final c in sky.clouds) {
      canvas.drawImage(c.image, c.at, paint);
    }
  }

  @override
  bool shouldRepaint(_StillPainter old) => old.sky != sky;
}

/// What moves, as a plain function of time: some stars twinkle, a
/// shooting star crosses now and then.
class _LivePainter extends CustomPainter {
  _LivePainter(this.sky, this.time) : super(repaint: time);

  final _Sky sky;
  final ValueListenable<double> time;

  /// A shooting star may cross once every [_period] s, for [_flight] s.
  static const _period = 5.5, _flight = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final paint = Paint()..isAntiAlias = false;
    for (final s in sky.stars) {
      if (!s.twinkles) continue;
      final glow = .5 + .5 * math.sin(t * 1.7 + s.phase);
      paint.color = s.color.withValues(alpha: s.color.a * (.2 + .8 * glow * glow));
      canvas.drawRect(s.at & Size(s.size, s.size), paint);
    }
    _shootingStar(canvas, size, t, paint);
  }

  /// Two times out of three, a shooting star: from high up, down to the
  /// left, a trail of squares — its head bright, then our blue (or our
  /// orange), fading — a small cross of light on its head.
  void _shootingStar(Canvas canvas, Size size, double t, Paint paint) {
    final slot = (t / _period).floor();
    final u = t - slot * _period;
    if (slot % 3 == 2 || u > _flight) return;
    final rng = math.Random(slot * 7919 + sky.seed);
    final start = Offset(size.width * (.35 + .6 * rng.nextDouble()), size.height * (-.05 + .3 * rng.nextDouble()));
    final angle = math.pi * (.78 + .08 * rng.nextDouble());
    final dir = Offset(math.cos(angle), math.sin(angle));
    final travel = size.shortestSide * (.55 + .3 * rng.nextDouble());
    final palette = slot.isEven ? PixelFxPalette.blue : PixelFxPalette.fire;
    final p = Curves.easeOut.transform(u / _flight);
    final head = start + dir * travel * p;
    // It fades at the end of its flight.
    final fade = (1 - (p - .75) / .25).clamp(0.0, 1.0);
    // White on the night; its own colour on the white.
    final headColour = sky.look == _Look.night ? const Color(0xFFFFFFFF) : palette.levels[2];
    const steps = 26;
    for (var i = steps; i >= 0; i--) {
      final k = i / steps;
      final at = (head - dir * (i * 4.0)).snap;
      final colour = i == 0
          ? headColour
          : Color.lerp(palette.levels[1], palette.levels[3], k)!.withValues(alpha: 1 - k * .85);
      paint.color = colour.withValues(alpha: colour.a * fade);
      final side = i < 8 ? 2.0 : 1.0;
      canvas.drawRect(at & Size(side, side), paint);
    }
    paint.color = palette.levels[1].withValues(alpha: .7 * fade);
    final h = head.snap;
    for (final d in const [Offset(3, 0), Offset(-2, 0), Offset(0, 3), Offset(0, -2)]) {
      canvas.drawRect((h + d) & const Size(1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_LivePainter old) => old.sky != sky || old.time != time;
}
