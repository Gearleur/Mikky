import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'feedback.dart';
import 'tokens.dart';

/// Pixel-art effects to try as agent indicators (user request,
/// 2026-09-30, after pictures of pixel sparkles, fireworks and galaxies):
/// a 9 × 9 grid of small square pixels, a little apart, no background;
/// empty pixels are not drawn. Shown in the kit only, to choose from.
enum PixelFxKind {
  /// A cross star that grows from a dot, throws rays and diagonal dots,
  /// then goes out; two small ones twinkle in the corners.
  sparkle,

  /// A burst in the middle, in eight directions, that opens as it lights
  /// up and closes again, over and over; the tips cool as it opens.
  firework,

  /// The same, calmer: in the eight directions, frame by frame — a small
  /// star, a middle one, a big one, the middle one again — keeping its
  /// colors (user requests, 2026-09-30).
  fireworkSoft,

  /// Spiral arms around a white core, turning slowly, scattered pixels on
  /// the edge.
  galaxy,
}

/// Four colors, from the brightest (the heart) to the darkest (the edge).
class PixelFxPalette {
  const PixelFxPalette(this.name, this.levels);

  final String name;
  final List<Color> levels;

  static const violet = PixelFxPalette('Violet', [Color(0xFFFFFFFF), Color(0xFFFF6BF5), Color(0xFFB026D6), Color(0xFF3A1AB8)]);
  static const blue = PixelFxPalette('Bleu', [Color(0xFFFFFFFF), Color(0xFF3FD8FF), Color(0xFF1E78FF), Color(0xFF0A22A8)]);
  static const fire = PixelFxPalette('Orange', [Color(0xFFFFF4B8), Color(0xFFFFB020), Color(0xFFFF5A1F), Color(0xFFA3140F)]);
  static const red = PixelFxPalette('Rouge', [Color(0xFFFFD6D2), Color(0xFFFF3B30), Color(0xFFC20A1E), Color(0xFF5E0610)]);

  static const yellow = PixelFxPalette('Jaune', [Color(0xFFFFF8D2), Color(0xFFFFD60A), Color(0xFFF2A900), Color(0xFF8A5A00)]);
  static const grey = PixelFxPalette('Gris', [Color(0xFFFFFFFF), Color(0xFFC7C7CC), Color(0xFF8E8E93), Color(0xFF48484A)]);

  static const all = [violet, blue, fire, red];

  /// The palette of an agent's state; finished takes the theme's green
  /// (the one of a done task's bubble).
  static PixelFxPalette of(UiStatus status, MikkyUi ui) => switch (status) {
    UiStatus.working => blue,
    UiStatus.thinking => violet,
    UiStatus.approval => fire,
    UiStatus.error => red,
    UiStatus.limited => yellow,
    UiStatus.sleeping => grey,
    UiStatus.finished => PixelFxPalette('Vert', [
      const Color(0xFFE3FCEA),
      ui.green,
      Color.lerp(ui.green, const Color(0xFF000000), .3)!,
      Color.lerp(ui.green, const Color(0xFF000000), .55)!,
    ]),
  };
}

/// An agent's state as a small pixel effect in its color — by default
/// the calm firework (user request, 2026-09-30), each state at its own
/// pace (see [_slow]); finished stays still, at a moment where it shows
/// well.
class StatusFx extends StatelessWidget {
  const StatusFx(this.status, {super.key, this.size = 16, this.kind = PixelFxKind.fireworkSoft});

  final UiStatus status;
  final double size;
  final PixelFxKind kind;

  /// Finished: the moment shown, still (seconds).
  static double _still(PixelFxKind kind) => switch (kind) {
    PixelFxKind.sparkle => .72,
    PixelFxKind.firework => 1.2,
    PixelFxKind.fireworkSoft => 1.0,
    PixelFxKind.galaxy => 1,
  };

  @override
  Widget build(BuildContext context) => PixelFx(
    kind: kind,
    palette: PixelFxPalette.of(status, MikkyUi.of(context)),
    size: size,
    at: status == UiStatus.finished ? _still(kind) : null,
    slow: _slow(status),
  );

  /// How slowly each state moves, against the effect's own pace (the calm
  /// firework: 3.6 s there and back): waiting fastest (1.2 s), then
  /// working (1.6 s), the others (2.4 s), asleep slowest (4.8 s) (user
  /// request, 2026-09-30).
  static double _slow(UiStatus s) => switch (s) {
    UiStatus.approval => 1 / 3,
    UiStatus.working => 1.6 / 3.6,
    UiStatus.sleeping => 4.8 / 3.6,
    _ => 2 / 3,
  };
}

class PixelFx extends StatelessWidget {
  const PixelFx({super.key, required this.kind, required this.palette, this.size = 36, this.at, this.slow = 1});

  final PixelFxKind kind;
  final PixelFxPalette palette;
  final double size;

  /// Seconds: shows that moment, still (to look at frames).
  final double? at;

  /// Plays this many times slower.
  final double slow;

  /// The calm firework needs only 7 × 7: bigger pixels when small.
  static int gridOf(PixelFxKind kind) => kind == PixelFxKind.fireworkSoft ? 7 : 9;

  @override
  Widget build(BuildContext context) {
    // On a light background a white heart would be a hole: a light tint of
    // the color instead.
    final levels = palette.levels;
    final shown = MikkyUi.of(context).isLight && levels.first.computeLuminance() > .8
        ? PixelFxPalette(palette.name, [Color.lerp(levels[1], const Color(0xFFFFFFFF), .45)!, ...levels.skip(1)])
        : palette;
    return _build(shown);
  }

  Widget _build(PixelFxPalette palette) => at != null
      ? CustomPaint(size: Size.square(size), painter: _FxPainter(kind, palette, at!))
      : Looping(
    key: ValueKey((kind, palette.name)),
    period: const Duration(seconds: 24),
    frozenAt: .03,
    builder: (context, t) => CustomPaint(size: Size.square(size), painter: _FxPainter(kind, palette, t * 24 / slow)),
  );
}

class _FxPainter extends CustomPainter {
  _FxPainter(this.kind, this.palette, this.t);

  final PixelFxKind kind;
  final PixelFxPalette palette;

  /// Seconds.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final n = PixelFx.gridOf(kind), c = n ~/ 2;
    final side = size.shortestSide;
    final gap = side * .018;
    final cell = (side - gap * (n - 1)) / n;
    final paint = Paint();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final i = switch (kind) {
          PixelFxKind.sparkle => _sparkle(x - c, y - c),
          PixelFxKind.firework => _firework(x - c, y - c),
          PixelFxKind.fireworkSoft => _fireworkSoft(x - c, y - c),
          PixelFxKind.galaxy => _galaxy(x - c, y - c, x, y),
        };
        final level = _level(i);
        if (level == null) continue;
        paint.color = palette.levels[level];
        canvas.drawRect(Rect.fromLTWH(x * (cell + gap), y * (cell + gap), cell, cell), paint);
      }
    }
  }

  /// Pixel art: a few flat colors, no blending. Null: not drawn.
  static int? _level(double i) => i > .82
      ? 0
      : i > .58
      ? 1
      : i > .34
      ? 2
      : i > .14
      ? 3
      : null;

  // ------------------------------------------------------------ sparkle

  double _sparkle(int dx, int dy) {
    // The big star: born, grows, goes out, rests (1.8 s).
    final main = _star(dx, dy, (t / 1.8) % 1, 4);
    // Two small ones in the corners, out of step.
    final a = _star(dx + 3, dy + 3, (t / 1.3 + .4) % 1, 1);
    final b = _star(dx - 3, dy - 3, (t / 1.5 + .75) % 1, 1);
    return math.max(main, math.max(a, b));
  }

  /// A cross star at the origin, [reach] pixels at most, at phase [p].
  static double _star(int dx, int dy, double p, int reach) {
    if (p > .8) return 0;
    final s = math.sin(p / .8 * math.pi);
    final ax = dx.abs(), ay = dy.abs();
    if (ax == 0 && ay == 0) return .35 + .65 * s;
    final len = reach * s;
    // The rays: bright near the heart, darker at the tip.
    if ((ax == 0 || ay == 0) && ax + ay <= len + .5) return s * (1 - (ax + ay) / (len + 1.2)) + .15;
    // Dots on the diagonals, a step away, once the star is big.
    if (reach > 1 && ax == ay && ax == (len > 2.6 ? 2 : 1) && s > .5) return .3 + .2 * s;
    return 0;
  }

  // ----------------------------------------------------------- firework

  double _firework(int dx, int dy) {
    // No launch: it stays in the middle, opens as it lights up, then
    // closes again, over and over (user request, 2026-09-30).
    final e = (1 - math.cos((t / 2.4) * math.pi * 2)) / 2;
    final r = .7 + e * 3.3;
    if (dx == 0 && dy == 0) return 1 - .15 * e;
    final d = math.sqrt((dx * dx + dy * dy).toDouble());
    // Along the eight directions, and the ones in between once it is open.
    final angle = math.atan2(dy.toDouble(), dx.toDouble());
    final onDir = (angle / (math.pi / 4) - (angle / (math.pi / 4)).roundToDouble()).abs() < .12;
    final between = (angle / (math.pi / 8) - (angle / (math.pi / 8)).roundToDouble()).abs() < .1 && e > .45;
    if (!onDir && !between) return 0;
    // The head of each spark, and a short trail behind it.
    final head = 1 - ((d - r).abs() / 1.1);
    final trail = d < r ? (1 - (r - d) / 3.2) * .7 : 0;
    // Open, it cools a little: white small, deeper colors at its widest.
    final cool = 1 - e * .35;
    return math.max(0, math.max(head, trail)) * cool * (between ? .75 : 1);
  }

  /// Frame by frame, like a sprite: a small star, the middle one, the big
  /// one, the middle one again (user requests, 2026-09-30: more than two
  /// steps, but no burst).
  double _fireworkSoft(int dx, int dy) {
    const frames = [0, 1, 2, 1];
    final frame = frames[((t / 3.6) % 1 * frames.length).floor()];
    return softFrame(frame, dx, dy);
  }

  /// One frame of the calm firework: 0 small, 1 middle, 2 big.
  static double softFrame(int frame, int dx, int dy) {
    final ax = dx.abs(), ay = dy.abs();
    // The eight directions only: straight or diagonal.
    if (!(ax == 0 || ay == 0 || ax == ay)) return 0;
    final straight = ax == 0 || ay == 0;
    final step = math.max(ax, ay);
    if (step == 0) return 1;
    switch (frame) {
      case 0: // Small star: the heart, its ring, short arms.
        if (step == 1) return straight ? .7 : .45;
        if (step == 2) return straight ? .3 : 0;
        return 0;
      case 1: // Middle star.
        if (step == 1) return straight ? .72 : .6;
        if (step == 2) return straight ? .45 : .3;
        return 0;
      default: // Big star.
        if (step == 1) return straight ? .75 : .62;
        if (step == 2) return straight ? .55 : .35;
        return straight ? .3 : 0;
    }
  }

  // ------------------------------------------------------------- galaxy

  double _galaxy(int dx, int dy, int x, int y) {
    final r = math.sqrt((dx * dx + dy * dy).toDouble());
    if (r < .5) return 1;
    final theta = math.atan2(dy.toDouble(), dx.toDouble());
    // Two arms winding out, turning once in 9 s.
    if (r > 4.6) return 0;
    final wave = .5 + .5 * math.cos(2 * theta - 1.7 * r + t * (math.pi * 2 / 9));
    // Thin arms: only the crest of the wave.
    final arm = math.pow(wave, 5).toDouble();
    final fade = math.exp(-r / 2.8);
    // A little grain, the same for a pixel, so the edges scatter.
    final grain = .7 + .6 * _hash(x * 17 + y * 31);
    final twinkle = r > 2.5 && _hash(x * 7 + y * 13 + (t * 3).floor()) > .95 ? .4 : 0.0;
    final core = r < 1.1 ? .75 : 0.0;
    return math.max(math.max(arm * (.3 + fade * 1.3) * grain, core), twinkle);
  }

  static double _hash(int i) {
    var h = i * 374761393 + 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return ((h ^ (h >> 16)) & 0xffff) / 0xffff;
  }

  @override
  bool shouldRepaint(_FxPainter old) => old.t != t || old.kind != kind || old.palette != palette;
}
