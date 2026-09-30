import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'motion.dart';
import 'pixel_fx.dart';
import 'status.dart';
import 'surface.dart';
import 'tokens.dart';

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

/// `.status`: an agent's state in a 28 px box — a small pixel firework
/// in the state's color ([StatusFx]; user request, 2026-09-30).
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key});

  final UiStatus status;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: 28, child: Center(child: StatusFx(status)));

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
