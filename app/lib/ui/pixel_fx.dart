import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'motion.dart';
import 'status.dart';
import 'tokens.dart';

/// Four colors, from the brightest (the heart) to the darkest (the edge).
class PixelFxPalette {
  const PixelFxPalette(this.name, this.levels);

  final String name;
  final List<Color> levels;

  /// On a light background a white heart would be a hole: a light tint of
  /// the color instead.
  PixelFxPalette on(MikkyUi ui) => ui.isLight && levels.first.computeLuminance() > .8
      ? PixelFxPalette(name, [Color.lerp(levels[1], const Color(0xFFFFFFFF), .45)!, ...levels.skip(1)])
      : this;

  static const violet = PixelFxPalette('Violet', [Color(0xFFFFFFFF), Color(0xFFFF6BF5), Color(0xFFB026D6), Color(0xFF3A1AB8)]);
  static const blue = PixelFxPalette('Bleu', [Color(0xFFFFFFFF), Color(0xFF3FD8FF), Color(0xFF1E78FF), Color(0xFF0A22A8)]);
  static const fire = PixelFxPalette('Orange', [Color(0xFFFFF4B8), Color(0xFFFFB020), Color(0xFFFF5A1F), Color(0xFFA3140F)]);
  static const red = PixelFxPalette('Rouge', [Color(0xFFFFD6D2), Color(0xFFFF3B30), Color(0xFFC20A1E), Color(0xFF5E0610)]);

  static const yellow = PixelFxPalette('Jaune', [Color(0xFFFFF8D2), Color(0xFFFFD60A), Color(0xFFF2A900), Color(0xFF8A5A00)]);
  static const grey = PixelFxPalette('Gris', [Color(0xFFFFFFFF), Color(0xFFC7C7CC), Color(0xFF8E8E93), Color(0xFF48484A)]);

  static const all = [violet, blue, fire, red];

  /// The signature colors (user request, 2026-09-30): the orange of their
  /// picture, and the same tints and steps in blue.
  static const signatureOrange = PixelFxPalette('Orange signature', [Color(0xFFFF8204), Color(0xFFFA500F), Color(0xFFE51300), Color(0xFFC4001D)]);
  static const signatureBlue = PixelFxPalette('Bleu signature', [Color(0xFF04BCFF), Color(0xFF0F84FA), Color(0xFF0045E5), Color(0xFF000DC4)]);

  /// The theme's green (the one of a done task's bubble).
  static PixelFxPalette green(MikkyUi ui) => PixelFxPalette('Vert', [
    const Color(0xFFE3FCEA),
    ui.green,
    Color.lerp(ui.green, const Color(0xFF000000), .3)!,
    Color.lerp(ui.green, const Color(0xFF000000), .55)!,
  ]);

  /// The palette of an agent's state; finished takes the theme's green
  /// (the one of a done task's bubble).
  static PixelFxPalette of(UiStatus status, MikkyUi ui) => switch (status) {
    UiStatus.working => blue,
    UiStatus.approval => fire,
    UiStatus.error => red,
    UiStatus.limited => yellow,
    UiStatus.paused => grey,
    UiStatus.finished => green(ui),
  };
}

/// Pixel art: a few flat colors, no blending. A pixel's brightness (0 to
/// 1) gives the index of its color in a [PixelFxPalette]; null: not drawn.
int? pixelLevel(double i) => i > .82
    ? 0
    : i > .58
    ? 1
    : i > .34
    ? 2
    : i > .14
    ? 3
    : null;

/// A fixed number from 0 to 1 for [i]: grain and twinkles that do not
/// change from one frame to the next.
double pixelHash(int i) {
  var h = i * 374761393 + 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0xffff) / 0xffff;
}

/// Paints [n] × [n] small square pixels, a little apart ([gap], against the
/// side), no background; [colorOf] gives each one's color, null: empty.
void paintPixelGrid(Canvas canvas, Size size, int n, Color? Function(int x, int y) colorOf, {double gap = .018}) {
  final side = size.shortestSide;
  final space = side * gap;
  final cell = (side - space * (n - 1)) / n;
  final paint = Paint();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final color = colorOf(x, y);
      if (color == null) continue;
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(x * (cell + space), y * (cell + space), cell, cell), paint);
    }
  }
}

/// A pixel effect for an agent indicator (user request, 2026-09-30, after
/// pictures of pixel sparkles, fireworks and galaxies): how bright each
/// pixel of its grid is, at any moment. The one in use is
/// [calmFirework]; others are tried on the boards (`trials/`).
abstract class PixelEffect {
  const PixelEffect();

  /// The effect of the states that go on by themselves (working, limit,
  /// finished).
  static const calmFirework = CalmFirework();

  /// The effect of what needs the user (a yes / no, a question, an error).
  static const exclamation = Exclamation();

  /// Pixels on a side.
  int get grid;

  /// Seconds: a moment where it shows well, shown still (finished).
  double get still;

  /// The brightness, from 0 to 1, of the pixel [dx], [dy] away from the
  /// middle, at [t] seconds.
  double at(double t, int dx, int dy);
}

/// The calm firework (user requests, 2026-09-30): in the eight
/// directions, frame by frame like a sprite — a small star, a middle one,
/// a big one, the middle one again (3.6 s) — keeping its colors; more
/// than two steps, but no burst.
class CalmFirework extends PixelEffect {
  const CalmFirework();

  /// It needs only 7 × 7: bigger pixels when small.
  @override
  int get grid => 7;

  @override
  double get still => 1.0;

  @override
  double at(double t, int dx, int dy) {
    const frames = [0, 1, 2, 1];
    return frame(frames[((t / 3.6) % 1 * frames.length).floor()], dx, dy);
  }

  /// One frame: 0 small, 1 middle, 2 big.
  static double frame(int frame, int dx, int dy) {
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
}

/// « ! » in pixels (user request, 2026-10-01: an exclamation for what
/// needs the user's OK): the bar and its dot, lit from the top, frame by
/// frame like the firework — plain, lit, lit with a glow, lit.
class Exclamation extends PixelEffect {
  const Exclamation();

  @override
  int get grid => 7;

  @override
  double get still => 1.0;

  @override
  double at(double t, int dx, int dy) {
    const frames = [0, 1, 2, 1];
    return frame(frames[((t / 3.6) % 1 * frames.length).floor()], dx, dy);
  }

  /// One frame: 0 plain, 1 lit, 2 lit with a glow. The bar is 3 pixels
  /// wide at the top, 1 lower down, then the dot: it reads at 18 px.
  static double frame(int frame, int dx, int dy) {
    final ax = dx.abs();
    final wide = dy == -3 || dy == -2, narrow = dy == -1 || dy == 0, dot = dy == 2;
    if ((wide && ax <= 1) || ((narrow || dot) && ax == 0)) {
      // A glint at the top, while lit.
      if (frame > 0 && dy == -3 && dx == 0) return .9;
      return narrow ? .45 : .7;
    }
    if (frame == 2 && ax == 2 && wide) return .2;
    return 0;
  }
}

/// The violet star of « Ensorcelé » (relaunched by itself when its limit
/// lifts): the only violet, no agent state uses it (2026-10-01).
class SpellFx extends StatelessWidget {
  const SpellFx({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => PixelFx(palette: PixelFxPalette.violet, size: size, slow: 2 / 3);
}

/// An agent's state as a small pixel effect in its color — the calm
/// firework (user request, 2026-09-30), each state at its own pace (see
/// [_slow]); finished stays still, at a moment where it shows well.
class StatusFx extends StatelessWidget {
  const StatusFx(this.status, {super.key, this.size = 16, this.effect});

  final UiStatus status;
  final double size;

  /// Another effect to try (boards); else the state's own.
  final PixelEffect? effect;

  /// The state's own effect: « ! » for what needs the user.
  static PixelEffect effectOf(UiStatus s) =>
      s == UiStatus.approval || s == UiStatus.error ? PixelEffect.exclamation : PixelEffect.calmFirework;

  @override
  Widget build(BuildContext context) {
    // Paused or idle: nothing goes on, nothing moves (its place is kept).
    if (status == UiStatus.paused) return SizedBox.square(dimension: size);
    final effect = this.effect ?? effectOf(status);
    return PixelFx(
      effect: effect,
      palette: PixelFxPalette.of(status, MikkyUi.of(context)),
      size: size,
      at: status == UiStatus.finished ? effect.still : null,
      slow: _slow(status),
    );
  }

  /// How slowly each state moves, against the effect's own pace (the calm
  /// firework: 3.6 s there and back): waiting fastest (1.2 s), then
  /// working (1.6 s), the others (2.4 s), asleep slowest (4.8 s) (user
  /// request, 2026-09-30).
  static double _slow(UiStatus s) => switch (s) {
    UiStatus.approval => 1 / 3,
    UiStatus.working => 1.6 / 3.6,
    _ => 2 / 3,
  };
}

/// A [PixelEffect] in a [palette], looping or still.
class PixelFx extends StatelessWidget {
  const PixelFx({super.key, this.effect = PixelEffect.calmFirework, required this.palette, this.size = 36, this.at, this.slow = 1});

  final PixelEffect effect;
  final PixelFxPalette palette;
  final double size;

  /// Seconds: shows that moment, still (to look at frames).
  final double? at;

  /// Plays this many times slower.
  final double slow;

  @override
  Widget build(BuildContext context) {
    // On a light background a white heart would be a hole: a light tint of
    // the color instead.
    final palette = this.palette.on(MikkyUi.of(context));
    return at != null
        ? CustomPaint(size: Size.square(size), painter: _FxPainter(effect, palette, at!))
        : Looping(
            key: ValueKey((effect, palette.name)),
            period: const Duration(seconds: 24),
            frozenAt: .03,
            builder: (context, t) => CustomPaint(size: Size.square(size), painter: _FxPainter(effect, palette, t * 24 / slow)),
          );
  }
}

class _FxPainter extends CustomPainter {
  _FxPainter(this.effect, this.palette, this.t);

  final PixelEffect effect;
  final PixelFxPalette palette;

  /// Seconds.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final n = effect.grid, c = n ~/ 2;
    paintPixelGrid(canvas, size, n, (x, y) {
      final level = pixelLevel(effect.at(t, x - c, y - c));
      return level == null ? null : palette.levels[level];
    });
  }

  @override
  bool shouldRepaint(_FxPainter old) => old.t != t || old.effect != effect || old.palette != palette;
}

/// A small firework star that does not move: the heart, its ring, four
/// short arms, on 5 × 5 pixels (user request, 2026-09-30: the steps of a
/// task and the grey groups of the home, one star each, in its color).
class PixelStar extends StatelessWidget {
  const PixelStar(this.palette, {super.key, this.size = 10});

  final PixelFxPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _StarPainter(palette.on(MikkyUi.of(context))));
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.palette);

  final PixelFxPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const c = 2;
    paintPixelGrid(canvas, size, 5, gap: .02, (x, y) {
      final level = pixelLevel(CalmFirework.frame(0, x - c, y - c));
      return level == null ? null : palette.levels[level];
    });
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.palette != palette;
}
