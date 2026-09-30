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

/// Behind [child], a field of small dots, invisible until a soft patch of
/// light in the state's color slides slowly over them from left to right,
/// leaving a short trail; then a pause (user request, 2026-09-30, after a
/// halftone glow they showed).
class DotGlow extends StatelessWidget {
  const DotGlow({super.key, required this.status, required this.child, this.radius = 18});

  final UiStatus status;
  final Widget child;

  /// The field is clipped to this rounded shape.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(MikkyUi.of(context), status);
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Looping(
              key: ValueKey(status),
              period: const Duration(milliseconds: 6500),
              frozenAt: .3,
              builder: (context, t) => CustomPaint(painter: _GlowPainter(t, color)),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.t, this.color);

  final double t;
  final Color color;

  /// Distance between two dots, and the biggest dot's radius.
  static const pitch = 4.5, big = 1.35;

  /// Part of the period the pass takes; the rest is a pause, all dark.
  static const pass = .82;

  /// How far the light reaches ahead of its center, and behind (the trail).
  static const ahead = 34.0, behind = 80.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (t > pass) return;
    final p = Curves.easeInOutSine.transform(t / pass);
    final head = -ahead * 2 + p * (size.width + ahead * 2 + behind * 2);
    final cy = size.height / 2;
    final paint = Paint()..color = color;
    final x0 = math.max(0, ((head - behind * 2.2) / pitch).floor());
    final x1 = math.min((size.width / pitch).ceil(), ((head + ahead * 2.2) / pitch).ceil());
    final rows = (size.height / pitch).ceil();
    for (var c = x0; c <= x1; c++) {
      final x = c * pitch + pitch / 2;
      final d = x - head;
      final along = d > 0 ? math.exp(-(d / ahead) * (d / ahead)) : math.exp(-(d / behind) * (d / behind));
      for (var r = 0; r < rows; r++) {
        final y = r * pitch + pitch / 2;
        final v = (y - cy) / (size.height * .4);
        // A little grain, always the same for a given dot.
        final grain = .8 + .4 * _hash(c, r);
        final i = along * math.exp(-v * v) * grain;
        if (i < .1) continue;
        // Halftone: the dots grow toward the center more than they darken.
        paint.color = color.withValues(alpha: .1 + .32 * math.min(1, i));
        canvas.drawCircle(Offset(x, y), big * (.3 + .7 * math.min(1, i)), paint);
      }
    }
  }

  static double _hash(int a, int b) {
    var h = a * 374761393 + b * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return ((h ^ (h >> 16)) & 0xffff) / 0xffff;
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.t != t || old.color != color;
}

/// A snake of lit dots running round a 4 × 4 grid of faint dots, in the
/// state's color: a small launcher that says « at work » (user request,
/// 2026-09-30, after Grok's loader).
class DotSnake extends StatelessWidget {
  const DotSnake(this.status, {super.key});

  final UiStatus status;

  static const pitch = 5.4, dot = 3.6;
  static const size = 3 * pitch + dot;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(MikkyUi.of(context), status);
    return Looping(
      key: ValueKey(status),
      period: const Duration(milliseconds: 2400),
      frozenAt: .3,
      builder: (context, t) => CustomPaint(size: const Size.square(size), painter: _SnakePainter(t, color)),
    );
  }
}

class _SnakePainter extends CustomPainter {
  _SnakePainter(this.t, this.color);

  final double t;
  final Color color;

  /// A closed path through the 16 dots (column, row), each next to the last.
  static const path = [
    (0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (2, 1), (1, 1), (1, 2),
    (2, 2), (3, 2), (3, 3), (2, 3), (1, 3), (0, 3), (0, 2), (0, 1),
  ];

  /// How many dots the snake lights, head included.
  static const length = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final head = t * path.length;
    final paint = Paint();
    for (var k = 0; k < path.length; k++) {
      // How far behind the head this dot is, along the path.
      final behind = (head - k) % path.length;
      final lit = behind < 1 ? behind : (behind < length ? 1 - (behind - 1) / (length - 1) : 0.0);
      final i = Curves.easeOut.transform(lit.clamp(0.0, 1.0));
      final (c, r) = path[k];
      paint.color = color.withValues(alpha: .14 + .86 * i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(c * DotSnake.pitch + DotSnake.dot / 2, r * DotSnake.pitch + DotSnake.dot / 2),
            width: DotSnake.dot * (.8 + .2 * i),
            height: DotSnake.dot * (.8 + .2 * i),
          ),
          const Radius.circular(1.1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SnakePainter old) => old.t != t || old.color != color;
}

/// A tool's logo that turns slowly and breathes while its agent works,
/// like Claude Code's star (user request, 2026-09-30).
class SpinningLogo extends StatelessWidget {
  const SpinningLogo({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Looping(
    period: const Duration(milliseconds: 3200),
    builder: (context, t) {
      final breath = (1 - math.cos(t * 4 * math.pi)) / 2;
      return Transform.rotate(
        angle: Curves.easeInOutCubic.transform(t) * math.pi,
        child: Transform.scale(scale: .84 + .16 * breath, child: child),
      );
    },
  );
}

/// `.status`: a 10 px dot in a 28 px box, animated by state: working =
/// blue with a widening wave (1.6 s); thinking, limited, sleeping = it
/// breathes (2.4 s, 3.2 s, 4 s); waiting for a yes = two hops then a
/// pause (1.8 s, 5 px); finished = green check that pops (550 ms);
/// error = one shake (450 ms).
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key});

  final UiStatus status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(MikkyUi.of(context), status);
    Widget dot(double size, {Widget? child}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: child,
    );
    final Widget inner = switch (status) {
      UiStatus.working => Looping(
        key: const ValueKey('working'),
        period: const Duration(milliseconds: 1600),
        frozenAt: 1,
        builder: (context, t) {
          final e = const Cubic(.2, .6, .3, 1).transform(t);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.scale(
                scale: 1 + 1.8 * e,
                child: Opacity(opacity: .5 * (1 - e), child: dot(10)),
              ),
              dot(10),
            ],
          );
        },
      ),
      UiStatus.thinking || UiStatus.limited || UiStatus.sleeping => Looping(
        key: ValueKey(status),
        period: Duration(
          milliseconds: switch (status) {
            UiStatus.thinking => 2400,
            UiStatus.limited => 3200,
            _ => 4000,
          },
        ),
        builder: (context, t) {
          final b = (1 - math.cos(t * 2 * math.pi)) / 2;
          final e = Curves.easeInOut.transform(b);
          return Opacity(
            opacity: (1 - .45 * e) * (status == UiStatus.sleeping ? .7 : 1),
            child: Transform.scale(scale: 1 - .28 * e, child: dot(10)),
          );
        },
      ),
      UiStatus.approval => Looping(
        key: const ValueKey('approval'),
        period: const Duration(milliseconds: 1800),
        builder: (context, t) => Transform.translate(offset: Offset(0, -5 * _hop(t)), child: dot(10)),
      ),
      UiStatus.finished => Looping(
        key: const ValueKey('finished'),
        period: const Duration(milliseconds: 550),
        repeat: false,
        builder: (context, t) => Transform.scale(
          scale: .3 + .7 * const Cubic(.34, 1.8, .64, 1).transform(t),
          child: dot(18, child: const MikkyIcon('check', size: 11, color: Color(0xFFFFFFFF), stroke: 3)),
        ),
      ),
      UiStatus.error => Looping(
        key: const ValueKey('error'),
        period: const Duration(milliseconds: 450),
        repeat: false,
        builder: (context, t) => Transform.translate(offset: Offset(_shake(t), 0), child: dot(10)),
      ),
    };
    return SizedBox.square(dimension: 28, child: Center(child: inner));
  }

  /// `@keyframes hop`: up 5 px at 10 % and 30 %, down at 20 % and 42 %.
  static double _hop(double t) {
    double up(double a, double b) => Cubic(.3, 0, .5, 1).transform(((t - a) / (b - a)).clamp(0, 1));
    double down(double a, double b) => 1 - const Cubic(.5, 0, .7, 1).transform(((t - a) / (b - a)).clamp(0, 1));
    if (t < .1) return up(0, .1);
    if (t < .2) return down(.1, .2);
    if (t < .3) return up(.2, .3);
    if (t < .42) return down(.3, .42);
    return 0;
  }

  /// `@keyframes shake`: -3, 3, -2, 1 px.
  static double _shake(double t) {
    const keys = [0.0, -3.0, 3.0, -2.0, 1.0, 0.0];
    final x = t * 5;
    final i = x.floor().clamp(0, 4);
    return keys[i] + (keys[i + 1] - keys[i]) * (x - i);
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
