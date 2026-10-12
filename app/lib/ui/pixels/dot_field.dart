import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../foundation/motion.dart';
import '../foundation/tokens.dart';
import 'pixel_fx.dart';

/// Small grey dots behind the notch's apps (2026-10-05, chosen on the
/// boards): « glitched », big squares of 6 × 6 dots more or less present,
/// sprinkled with small bright ones (2 × 2); 1.2 px dots every 8 px, a
/// texture from afar. Whole under the apps ([solidFrom] and beyond), they
/// drop out at random towards [goneAt], in Mikky's part, where none are
/// left — a soft line between the two parts; they fade at the top and the
/// bottom too, and only a little on the right.
///
/// They live, barely (2026-10-05: « presque pas perceptible »): a few
/// dots light up slowly and go out, now and then a big square glitches
/// for a blink, and rarely a tiny pixel firework goes off among them. The
/// dots themselves are painted once; only that thin layer moves, at 15
/// images a second, on the [DecorClock], and not at all when the island is
/// hidden or Windows asks for fewer animations.
class DotField extends StatefulWidget {
  const DotField({super.key, required this.solidFrom, required this.goneAt, this.seed = 5, this.at});

  /// From this x on, the dots are whole; at [goneAt] (left of it), gone.
  final double solidFrom, goneAt;
  final int seed;

  /// Shows that moment (seconds) of the layer that moves, without the
  /// clock (to look at it on a still image).
  final double? at;

  @override
  State<DotField> createState() => _DotFieldState();
}

class _DotFieldState extends State<DotField> with DecorTicks {
  /// Seconds on the clock, every other tick of it (15 a second).
  @override
  double? get decorStill => widget.at;

  /// The dots, laid out once for a size.
  _Dots? _dots;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    // Grey, a little dark (« pas assez noir » paler): a texture, not a
    // pattern to read.
    final color = ui.isLight
        ? const Color(0xFF6E6E73).withValues(alpha: .7)
        : const Color(0xFFFFFFFF).withValues(alpha: .34);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final d = _dots;
          final dots =
              d != null &&
                  d.size == size &&
                  d.solidFrom == widget.solidFrom &&
                  d.goneAt == widget.goneAt &&
                  d.seed == widget.seed
              ? d
              : _dots = _Dots(size, widget.solidFrom, widget.goneAt, widget.seed);
          return Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(child: CustomPaint(painter: _DotsPainter(dots, color))),
              if (decorRuns || widget.at != null)
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _LivePainter(dots, color, decorTime, [
                      PixelFxPalette.blue.on(ui),
                      PixelFxPalette.fire.on(ui),
                      PixelFxPalette.violet.on(ui),
                      PixelFxPalette.green(ui).on(ui),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Where the dots are and how present each is (0: none), and how faded
/// its place is, one cell every [step] px.
class _Dots {
  _Dots(this.size, this.solidFrom, this.goneAt, this.seed)
    : cols = (size.width / step).ceil(),
      rows = (size.height / step).ceil() {
    strength = Float32List(cols * rows);
    fade = Float32List(cols * rows);
    final rng = math.Random(seed);
    // One strength per big square, at random, never nothing; a few small
    // squares bright.
    final big = <(int, int), double>{}, small = <(int, int), bool>{};
    double square(int c, int r) => big.putIfAbsent((
      c ~/ 6,
      r ~/ 6,
    ), () => rng.nextDouble() < .33 ? .85 + .15 * rng.nextDouble() : .14 + .26 * rng.nextDouble());
    bool sparkle(int c, int r) => small.putIfAbsent((c ~/ 2, r ~/ 2), () => rng.nextDouble() < .1);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = c * step + step / 2, y = r * step + step / 2;
        final left = _smooth(((x - goneAt) / (solidFrom - goneAt)).clamp(0.0, 1.0));
        final vertical = _smooth((y / _edge).clamp(0.0, 1.0)) * _smooth(((size.height - y) / _edge).clamp(0.0, 1.0));
        final right = 1 - (1 - _rightPale) * _smooth(((x - (size.width - _right)) / _right).clamp(0.0, 1.0));
        final f = left * vertical * right;
        fade[r * cols + c] = f;
        if (f <= 0) continue;
        final s = sparkle(c, r) ? 1.0 : square(c, r) * .8;
        // In the fade, dots drop out at random instead of only paling.
        if (f < 1 && rng.nextDouble() > f) continue;
        strength[r * cols + c] = s * (.5 + .5 * f);
      }
    }
  }

  final Size size;
  final double solidFrom, goneAt;
  final int seed, cols, rows;
  late final Float32List strength, fade;

  /// Between two dots (6 made « trop de points »); a dot's side (1.4 and
  /// 1.6 were « trop gros »).
  static const step = 8.0, dot = 1.2;

  /// The fade at the top and the bottom; on the right, its length and how
  /// pale it gets there (« un fondu plus léger sur la droite »).
  static const _edge = 44.0, _right = 90.0, _rightPale = .5;

  static double _smooth(double t) => t * t * (3 - 2 * t);

  /// A dot's square, at a cell.
  static Rect rect(int c, int r, [double dx = 0]) =>
      Rect.fromLTWH((c * step + step / 2 + dx).roundToDouble(), (r * step + step / 2).roundToDouble(), dot, dot);
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.dots, this.color);

  final _Dots dots;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var r = 0; r < dots.rows; r++) {
      for (var c = 0; c < dots.cols; c++) {
        final s = dots.strength[r * dots.cols + c];
        if (s == 0) continue;
        paint.color = color.withValues(alpha: color.a * s);
        canvas.drawRect(_Dots.rect(c, r), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.dots != dots || old.color != color;
}

/// What moves on the dots, as a plain function of time (no state): it
/// draws a few dozen squares at most.
class _LivePainter extends CustomPainter {
  _LivePainter(this.dots, this.color, this.time, this.palettes) : super(repaint: time);

  final _Dots dots;
  final Color color;
  final ValueListenable<double> time;
  final List<PixelFxPalette> palettes;

  /// How many dots light up at once, at most; their cycle (seconds).
  static const _twinkles = 20, _twinkleMin = 4.0, _twinkleMore = 4.0;

  /// A glitch every [_glitchEvery] seconds, somewhere in it; a firework
  /// every [_fireEvery], lasting [_fireLife].
  static const _glitchEvery = 4.5, _fireEvery = 15.0, _fireLife = 2.8;

  static double _h(int i) => pixelHash(i);

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final paint = Paint()..isAntiAlias = false;
    final n = dots.cols * dots.rows;
    if (n == 0) return;

    // Slow twinkles: a dot lights up and goes out over half its cycle, then
    // another one, elsewhere, on the next cycle.
    for (var i = 0; i < _twinkles; i++) {
      final period = _twinkleMin + _twinkleMore * _h(i * 7 + 1);
      final local = t + _h(i * 7 + 2) * period;
      final cycle = (local / period).floor();
      final u = local / period - cycle;
      if (u >= .5) continue;
      final cell = (_h(i * 9973 + cycle * 131) * n).floor().clamp(0, n - 1);
      final fade = dots.fade[cell];
      if (fade < .4) continue;
      final glow = math.pow(math.sin(math.pi * u / .5), 2).toDouble();
      paint.color = color.withValues(alpha: math.min(1, color.a * 1.6 * glow * fade));
      canvas.drawRect(_Dots.rect(cell % dots.cols, cell ~/ dots.cols), paint);
    }

    // A glitch: a big square's dots flicker, brighter, slipped by one
    // step, for a blink.
    final g = (t / _glitchEvery).floor();
    final gStart = g * _glitchEvery + _h(g * 3 + 1) * (_glitchEvery - 1.5);
    final gLife = .2 + .4 * _h(g * 3 + 2);
    if (t >= gStart && t < gStart + gLife) {
      final flick = ((t - gStart) / .066).floor();
      if (_h(g * 31 + flick) > .3) {
        final bigCols = (dots.cols / 6).ceil(), bigRows = (dots.rows / 6).ceil();
        final bc = (_h(g * 3 + 3) * bigCols).floor(), br = (_h(g * 3 + 4) * bigRows).floor();
        final slip = (_h(g * 3 + 5) < .5 ? -1.0 : 1.0) * _Dots.step;
        for (var r = br * 6; r < math.min(br * 6 + 6, dots.rows); r++) {
          for (var c = bc * 6; c < math.min(bc * 6 + 6, dots.cols); c++) {
            final s = dots.strength[r * dots.cols + c];
            if (s == 0) continue;
            final a = color.a * s * dots.fade[r * dots.cols + c];
            paint.color = color.withValues(alpha: math.min(1, a * 1.2));
            canvas.drawRect(_Dots.rect(c, r), paint);
            paint.color = color.withValues(alpha: a * .8);
            canvas.drawRect(_Dots.rect(c, r, slip), paint);
          }
        }
      }
    }

    // Rarely, a tiny firework among the whole dots: ours, 7 × 7 pixels of
    // 2 px, faint.
    final f = (t / _fireEvery).floor();
    final fStart = f * _fireEvery + 3 + _h(f * 5 + 1) * (_fireEvery - 3 - _fireLife);
    final fu = (t - fStart) / _fireLife;
    if (fu >= 0 && fu < 1) {
      const px = 2.0, half = 3;
      final left = dots.solidFrom + 24, right = size.width - 110, top = 40.0, bottom = size.height - 40;
      if (right > left && bottom > top) {
        final cx = (left + _h(f * 5 + 2) * (right - left)).roundToDouble();
        final cy = (top + _h(f * 5 + 3) * (bottom - top)).roundToDouble();
        final palette = palettes[(_h(f * 5 + 4) * palettes.length).floor().clamp(0, palettes.length - 1)];
        final frame = const [0, 1, 2, 2][(fu * 4).floor().clamp(0, 3)];
        final fade =
            (fu < .15
                ? fu / .15
                : fu > .55
                ? (1 - fu) / .45
                : 1.0) *
            .55;
        for (var dy = -half; dy <= half; dy++) {
          for (var dx = -half; dx <= half; dx++) {
            final level = pixelLevel(CalmFirework.frame(frame, dx, dy));
            if (level == null) continue;
            final c = palette.levels[level];
            paint.color = c.withValues(alpha: c.a * fade);
            canvas.drawRect(Rect.fromLTWH(cx + dx * px, cy + dy * px, px, px), paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_LivePainter old) => old.dots != dots || old.color != color || old.time != time;
}
