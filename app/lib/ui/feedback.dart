import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'icons.dart';
import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

/// A widget animated forever by one controller of [period]; stops (and
/// shows [frozenAt]) when Windows asks for fewer animations. [frozenAt]
/// is where the CSS animation ends, as the prototypes show with
/// `prefers-reduced-motion` (and their `#calme` captures).
class Looping extends StatefulWidget {
  const Looping({super.key, required this.period, required this.builder, this.frozenAt = 0, this.repeat = true});

  final Duration period;
  final Widget Function(BuildContext context, double t) builder;
  final double frozenAt;

  /// False: plays once (a pop, a shake).
  final bool repeat;

  @override
  State<Looping> createState() => _LoopingState();
}

class _LoopingState extends State<Looping> with SingleTickerProviderStateMixin {
  // One-shot (pop, shake): short, at 60 fps. Loops: on the DecorClock.
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);
  bool _onClock = false;
  Duration? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = Motion.reduced(context);
    if (!widget.repeat) {
      if (reduced) {
        _c.value = 1;
      } else if (_c.value == 0 && !_c.isAnimating) {
        _c.forward();
      }
      return;
    }
    final run = Motion.loops(context);
    if (!run && _onClock) {
      DecorClock.unlisten(_tick);
      _onClock = false;
    } else if (run && !_onClock) {
      DecorClock.listen(_tick);
      _onClock = true;
    }
  }

  void _tick() => setState(() {});

  double get _t {
    if (!_onClock) return widget.frozenAt;
    final now = DecorClock.now.value;
    final start = _start ??= now;
    final period = widget.period.inMicroseconds;
    return ((now - start).inMicroseconds % period) / period;
  }

  @override
  void dispose() {
    if (_onClock) DecorClock.unlisten(_tick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: widget.repeat ? widget.builder(context, _t) : AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, _c.value)),
  );
}

/// `.spin`: 16 px ring open on the right, one turn in 0.7 s.
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.color, this.size = 16});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? MikkyUi.of(context).text;
    return Looping(
      period: const Duration(milliseconds: 700),
      builder: (context, t) => Transform.rotate(
        angle: t * 2 * math.pi,
        child: CustomPaint(size: Size.square(size), painter: _SpinPainter(c)),
      ),
    );
  }
}

class _SpinPainter extends CustomPainter {
  _SpinPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // A CSS border with a transparent right side: three quarters of a ring.
    canvas.drawArc(r.deflate(1), -math.pi / 4 + math.pi / 2, 1.5 * math.pi, false, paint);
  }

  @override
  bool shouldRepaint(_SpinPainter old) => old.color != color;
}

/// `.progress`: a 4 px bar; [value] null: indeterminate (1.3 s).
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 4,
        color: ui.track,
        child: LayoutBuilder(
          builder: (context, box) {
            final bar = DecoratedBox(
              decoration: BoxDecoration(color: ui.ink, borderRadius: BorderRadius.circular(2)),
            );
            final v = value;
            if (v != null) {
              return Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(width: box.maxWidth * v.clamp(0, 1), child: bar),
              );
            }
            final w = box.maxWidth * .35;
            return Looping(
              period: const Duration(milliseconds: 1300),
              frozenAt: .4,
              builder: (context, t) {
                final e = const Cubic(.6, 0, .4, 1).transform(t);
                return Stack(
                  children: [Positioned(left: -w + e * w * 4, top: 0, bottom: 0, width: w, child: bar)],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// `.badge`: a number on an icon; `.dot-badge`: an amber dot that pops in.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, this.ring});

  final int count;

  /// The background around it (the island, or the board).
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 17),
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: ui.ink,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [BoxShadow(color: ring ?? ui.island, spreadRadius: 2)],
      ),
      // Shrink-wrapped: a Container with an alignment would fill the width
      // it is given (a long black bar in the tab bar).
      child: Center(
        widthFactor: 1,
        child: Text(
          '$count',
          style: uiText(10, weight: FontWeight.w600, color: ui.onInk, height: 1),
        ),
      ),
    );
  }
}

class DotBadge extends StatelessWidget {
  const DotBadge({super.key, this.show = true, this.ring});

  final bool show;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return AnimatedScale(
      scale: show ? 1 : 0,
      duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 350),
      curve: const Cubic(.34, 1.8, .64, 1),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: ui.amber,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: ring ?? ui.island, spreadRadius: 2)],
        ),
      ),
    );
  }
}

/// The look of an agent's state in the window (`.status`, « États d'un
/// agent »), from the island's [AgentStatus].
enum UiStatus {
  working,
  thinking,
  approval,
  finished,
  error,
  limited,
  sleeping;

  static UiStatus of(AgentStatus s) => switch (s) {
    AgentStatus.working || AgentStatus.searching => working,
    AgentStatus.thinking => thinking,
    AgentStatus.approval || AgentStatus.question => approval,
    AgentStatus.finished => finished,
    AgentStatus.error => error,
    AgentStatus.rateLimited => limited,
    AgentStatus.idle => sleeping,
  };
}

/// The color of a state: blue working, purple thinking, amber waiting…
Color statusColor(MikkyUi ui, UiStatus status) => switch (status) {
  UiStatus.working => ui.blue,
  UiStatus.thinking => ui.purple,
  UiStatus.approval => ui.amber,
  UiStatus.finished => ui.green,
  UiStatus.error => ui.red,
  UiStatus.limited => ui.yellow,
  UiStatus.sleeping => ui.grey,
};

/// A classic launcher: three square pixels running round the edge of a
/// 3 × 3 square, one step at a time, in the state's color; the tail fades
/// and the empty cells are gone (user request, 2026-09-30, after Grok's
/// loader). Set aside for now: only in the kit.
class DotSnake extends StatelessWidget {
  const DotSnake(this.status, {super.key});

  final UiStatus status;

  static const pitch = 6.0, pixel = 5.0;
  static const size = 2 * pitch + pixel;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(MikkyUi.of(context), status);
    return Looping(
      key: ValueKey(status),
      period: const Duration(milliseconds: 2000),
      frozenAt: .3,
      builder: (context, t) => CustomPaint(size: const Size.square(size), painter: _SnakePainter(t, color)),
    );
  }
}

class _SnakePainter extends CustomPainter {
  _SnakePainter(this.t, this.color);

  final double t;
  final Color color;

  /// Round the edge of the square, clockwise (column, row).
  static const path = [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)];

  /// The head, then the tail fading out.
  static const tail = [1.0, .5, .2];

  @override
  void paint(Canvas canvas, Size size) {
    final head = (t * path.length).floor() % path.length;
    final paint = Paint();
    for (var k = 0; k < tail.length; k++) {
      final (c, r) = path[(head - k) % path.length];
      paint.color = color.withValues(alpha: tail[k]);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(c * DotSnake.pitch, r * DotSnake.pitch, DotSnake.pixel, DotSnake.pixel),
          const Radius.circular(1.2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SnakePainter old) => old.t != t || old.color != color;
}

/// A tool's logo that turns and breathes while its agent works (user
/// request, 2026-09-30). Claude: half a turn that speeds up and slows
/// down, like its own star, every 3.2 s. Others: slower, one even turn in
/// 8 s, growing and shrinking a little twice meanwhile.
class SpinningLogo extends StatelessWidget {
  const SpinningLogo({super.key, required this.child, this.claude = false});

  final Widget child;
  final bool claude;

  @override
  Widget build(BuildContext context) => Looping(
    period: Duration(milliseconds: claude ? 3200 : 8000),
    builder: (context, t) {
      final breath = (1 - math.cos(t * 4 * math.pi)) / 2;
      final angle = claude ? Curves.easeInOutCubic.transform(t) * math.pi : t * 2 * math.pi;
      return Transform.rotate(
        angle: angle,
        child: Transform.scale(scale: (claude ? .84 : .88) + (claude ? .16 : .12) * breath, child: child),
      );
    },
  );
}

/// A small star that thinks: a bright core in a pale glow, thin orange
/// and pink rays of uneven lengths that tremble, the whole swaying a
/// little (user request, 2026-09-30, after a sparkler star; tried on
/// Mikky, then set aside here, like the launcher).
class ThinkingStar extends StatelessWidget {
  const ThinkingStar({super.key, this.size = 22});

  final double size;

  /// Long enough that the loop's seam never shows.
  static const _period = 30.0;

  @override
  Widget build(BuildContext context) => Looping(
    period: const Duration(seconds: 30),
    frozenAt: .02,
    builder: (context, t) => CustomPaint(size: Size.square(size), painter: _StarPainter(t * _period)),
  );
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.t);

  /// Seconds.
  final double t;

  static const core = Color(0xFFFFFFFF);
  static const glow = Color(0xFFBFE3FF);
  static const warm = Color(0xFFFF9A4D);
  static const pink = Color(0xFFFF5C8A);

  @override
  void paint(Canvas canvas, Size size) {
    final big = size.shortestSide / 2 * (1 + .05 * math.sin(t * 4.1));
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    // It stirs: a slow sway and a quicker shiver.
    canvas.rotate(.12 * math.sin(t * 1.7) + .04 * math.sin(t * 6.3));
    canvas.drawCircle(
      Offset.zero,
      big * .62,
      Paint()
        ..shader = RadialGradient(colors: [
          glow.withValues(alpha: .75),
          glow.withValues(alpha: .22),
          glow.withValues(alpha: 0),
        ], stops: const [0, .45, 1])
            .createShader(Rect.fromCircle(center: Offset.zero, radius: big * .62)),
    );
    const rays = 16;
    for (var i = 0; i < rays; i++) {
      // Fixed unevenness per ray, and each one trembles on its own.
      final h = _hash(i);
      final angle = i / rays * math.pi * 2 + (h - .5) * .22;
      final long = (i.isEven ? .78 : .48) + h * .28;
      final length = big * long * (1 + .14 * math.sin(t * (6 + h * 5) + h * 20));
      final base = big * (.025 + .018 * h);
      final dir = Offset(math.cos(angle), math.sin(angle));
      final side = Offset(-dir.dy, dir.dx) * base;
      final from = dir * (big * .08);
      final tip = dir * length;
      canvas.drawPath(
        Path()
          ..moveTo(from.dx + side.dx, from.dy + side.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(from.dx - side.dx, from.dy - side.dy)
          ..close(),
        Paint()
          ..shader = LinearGradient(colors: [
            core,
            warm.withValues(alpha: .95),
            (h > .5 ? pink : warm).withValues(alpha: 0),
          ], stops: const [0, .35, 1])
              .createShader(Rect.fromPoints(from, tip)),
      );
    }
    // The core: a small bright point with its own soft halo.
    canvas.drawCircle(
      Offset.zero,
      big * .2,
      Paint()
        ..shader = RadialGradient(colors: [core, core.withValues(alpha: .85), core.withValues(alpha: 0)], stops: const [0, .3, 1])
            .createShader(Rect.fromCircle(center: Offset.zero, radius: big * .2)),
    );
    canvas.restore();
  }

  static double _hash(int i) {
    var h = i * 374761393 + 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return ((h ^ (h >> 16)) & 0xffff) / 0xffff;
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.t != t;
}

/// A small square of 3 × 3 pixels in shades of the state's color, that
/// live like SmoothUI's agent avatar (MIT, © 2024 Eduardo Calvo): each
/// pixel pulses on its own, the whole breathes, a wave crosses it on the
/// diagonal and a pixel flashes now and then (user request, 2026-09-30).
/// Every state has one; finished is just a light green square, still.
/// [seed] gives another pattern, same colors.
class PixelStatus extends StatelessWidget {
  const PixelStatus(this.status, {super.key, this.size = 14, this.seed = 0});

  final UiStatus status;
  final double size;
  final int seed;

  /// Base hue, saturation and lightness of each state, in HSL.
  static (double, double, double) _base(UiStatus s) => switch (s) {
    UiStatus.working => (214, 90, 56),
    UiStatus.thinking => (276, 72, 60),
    UiStatus.approval => (30, 95, 55),
    UiStatus.finished => (142, 62, 48),
    UiStatus.error => (4, 88, 56),
    UiStatus.limited => (46, 95, 52),
    UiStatus.sleeping => (240, 4, 68),
  };

  /// Loops are long so their seam never shows (times in ms, as SmoothUI).
  static const _periodMs = 60000.0;

  /// Finished: just a light green square, still.
  static const _doneGreen = Color(0xFF6EDC8C);

  @override
  Widget build(BuildContext context) {
    if (status == UiStatus.finished) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: _doneGreen, borderRadius: BorderRadius.circular(size * .24)),
      );
    }
    final painter = _PixelPalette.of(_base(status), status.index * 7919 + seed);
    return Looping(
      key: ValueKey(status),
      period: const Duration(milliseconds: 60000),
      frozenAt: .01,
      builder: (context, t) => CustomPaint(size: Size.square(size), painter: _PixelPainter(painter, t * _periodMs)),
    );
  }
}

/// Three shades of one hue and the 3 × 3 cells, drawn once per state.
class _PixelPalette {
  _PixelPalette(this.colors, this.cells);

  final List<HSLColor> colors;

  /// Per cell: which shade, how bright, and its own phases.
  final List<(int, double, double, double)> cells;

  static final Map<(double, double, double, int), _PixelPalette> _cache = {};

  static _PixelPalette of((double, double, double) base, int seed) => _cache[(base.$1, base.$2, base.$3, seed)] ??= () {
    final rng = math.Random(seed);
    final (h, s, l) = base;
    // Neighbouring hues, as SmoothUI does, but closer (±20°): the state
    // must still read blue, orange or green.
    double hue() => (h - 20 + rng.nextDouble() * 40) % 360;
    HSLColor c(double hue, double sat, double light) =>
        HSLColor.fromAHSL(1, hue, (sat / 100).clamp(0.0, 1.0), (light / 100).clamp(0.0, 1.0));
    final colors = [c(h, s, l), c(hue(), s - 5 + rng.nextDouble() * 10, l - 12), c(hue(), s - 10, l + 10)];
    final cells = [
      for (var i = 0; i < 9; i++) (rng.nextInt(3), .55 + rng.nextDouble() * .45, rng.nextDouble() * math.pi * 2, rng.nextDouble() * math.pi * 2),
    ];
    return _PixelPalette(colors, cells);
  }();
}

class _PixelPainter extends CustomPainter {
  _PixelPainter(this.palette, this.ms);

  final _PixelPalette palette;

  /// Milliseconds; null: still.
  final double? ms;

  @override
  void paint(Canvas canvas, Size size) {
    final t = ms;
    final side = size.shortestSide;
    final half = side / 2;
    // The whole square breathes a little in size.
    final scale = t == null ? 1.0 : 1 + math.sin(t * .0008) * .03;
    canvas.save();
    canvas.translate(half, half);
    canvas.scale(scale);
    canvas.translate(-half, -half);
    final shape = RRect.fromRectAndRadius(Offset.zero & Size.square(side), Radius.circular(side * .24));
    // A soft glow of the main shade around it.
    canvas.drawRRect(
      shape,
      Paint()
        ..color = palette.colors.first.toColor().withValues(alpha: .35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * .18),
    );
    canvas.clipRRect(shape);
    final cell = side / 3;
    final breathe = t == null ? 0.0 : math.sin(t * .001) * 6;
    final paint = Paint();
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        final (shade, bright, phase, sparklePhase) = palette.cells[y * 3 + x];
        final base = palette.colors[shade];
        var light = base.lightness * 100;
        if (t != null) {
          final pulse = math.sin(t * .002 + phase) * 12;
          final wave = math.sin(t * .0015 + (x + y) / 1.5) * 9;
          final spark = math.sin(t * .004 + sparklePhase);
          light += pulse + breathe + wave + (spark > .92 ? (spark - .92) / .08 * 20 : 0);
        }
        light = (light * (.75 + .25 * bright)).clamp(22.0, 88.0);
        paint.color = base.withSaturation(math.min(1, base.saturation + .05)).withLightness(light / 100).toColor();
        // A hair of overlap, so no seam shows between the pixels.
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + .4, cell + .4), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PixelPainter old) => old.ms != ms || old.palette != palette;
}

/// `.status`: an agent's state in a 28 px box — a small square of pixels
/// in the state's color ([PixelStatus]; user request, 2026-09-30).
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key});

  final UiStatus status;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: 28, child: Center(child: PixelStatus(status)));

  /// `@keyframes hop`: up 5 px at 10 % and 30 %, down at 20 % and 42 %.
  static double hop(double t) {
    double up(double a, double b) => Cubic(.3, 0, .5, 1).transform(((t - a) / (b - a)).clamp(0, 1));
    double down(double a, double b) => 1 - const Cubic(.5, 0, .7, 1).transform(((t - a) / (b - a)).clamp(0, 1));
    if (t < .1) return up(0, .1);
    if (t < .2) return down(.1, .2);
    if (t < .3) return up(.2, .3);
    if (t < .42) return down(.3, .42);
    return 0;
  }
}

/// `.toast`: a notification bubble on top of the window; it drops with a
/// spring (300 / 0.62), stays 2.8 s, then rises and fades (220 ms).
class Toast extends StatelessWidget {
  const Toast({super.key, required this.icon, required this.title, required this.subtitle, this.action});

  final String icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Surface(
      radius: 24,
      color: ui.raise,
      shadows: [CssShadow(0, 0, 0, ui.hlEdge, spread: 1, inset: true), ...ui.shBar],
      padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: ui.ink, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: MikkyIcon(icon, size: 18, color: ui.onInk),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(13, weight: FontWeight.w600, color: ui.text, height: 1.35),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(12, color: ui.text2, height: 1.35),
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 10), action!],
        ],
      ),
    );
  }
}

/// `.looking` / `.typing`: three dots hopping in turn (1.2 s).
class TypingDots extends StatelessWidget {
  const TypingDots({super.key, this.size = 6, this.gap = 4, this.color});

  final double size, gap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? MikkyUi.of(context).text3;
    return Looping(
      period: const Duration(milliseconds: 1200),
      frozenAt: .9,
      builder: (context, t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Builder(
              builder: (context) {
                final p = ((t - i * .125) % 1 + 1) % 1;
                // 0 → 30 % up and bright, 60 % back down, then still.
                final k = p < .3 ? p / .3 : (p < .6 ? 1 - (p - .3) / .3 : 0.0);
                return Transform.translate(
                  offset: Offset(0, -3 * k),
                  child: Opacity(
                    opacity: .45 + .55 * k,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
