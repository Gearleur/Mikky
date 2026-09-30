import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'messages.dart';
import 'motion.dart';
import 'tokens.dart';

/// What a step of the metro line is (`.ti`, `ux-a.html`).
enum StepKind {
  /// Done: black dot with a check, grey text.
  done,

  /// The last step, done: green dot with a check, bold.
  end,

  /// At work: a blue ring that pulses, bold; the blue line creeps down.
  now,

  /// To do: a hollow dot, pale text.
  todo,

  /// A message from the user, slipped in between the steps.
  me,

  /// The agent's answer to it.
  it,
}

/// One step or message on the metro line of Suivi. The vertical line runs
/// through every item; [past] items have it black. [first] / [last] trim
/// it at the dots.
class MetroStep extends StatelessWidget {
  const MetroStep({super.key, required this.kind, required this.child, this.past = false, this.first = false, this.last = false, this.meta});

  final StepKind kind;
  final Widget child;
  final bool past, first, last;

  /// Under a message: time, folder…
  final String? meta;

  static const _lineX = 9.0, _lineW = 2.5, _dotY = 12.0;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final textColor = switch (kind) {
      StepKind.done => ui.text2,
      StepKind.todo => ui.text3,
      _ => ui.text,
    };
    final weight = kind == StepKind.end || kind == StepKind.now ? FontWeight.w600 : FontWeight.w400;
    Widget content = DefaultTextStyle(
      style: uiText(13, weight: weight, color: textColor, height: 18 / 13),
      child: child,
    );
    if (kind == StepKind.me || kind == StepKind.it) {
      final me = kind == StepKind.me;
      content = Column(
        crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          FractionallySizedBox(
            widthFactor: .88,
            alignment: me ? Alignment.centerRight : Alignment.centerLeft,
            child: Align(
              alignment: me ? Alignment.centerRight : Alignment.centerLeft,
              child: Bubble(me: me, thread: true, child: child),
            ),
          ),
          if (meta != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(meta!, style: uiText(11, color: ui.text3, height: 1.3)),
            ),
        ],
      );
    }
    final bottom = kind == StepKind.me || kind == StepKind.it ? 12.0 : 10.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _LinePainter(ui: ui, past: past, now: kind == StepKind.now, first: first, last: last),
          ),
        ),
        if (kind == StepKind.now) const Positioned.fill(child: _Flow()),
        Positioned(
          left: _lineX + _lineW / 2,
          top: _dotY,
          child: FractionalTranslation(translation: const Offset(-.5, -.5), child: _dot(ui)),
        ),
        Padding(padding: EdgeInsets.fromLTRB(30, 3, 0, bottom), child: content),
      ],
    );
  }

  Widget _dot(MikkyUi ui) {
    Widget circle(double size, Color fill, {Color? ring, double ringW = 0, Widget? child}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: ring == null ? null : Border.all(color: ring, width: ringW, strokeAlign: BorderSide.strokeAlignInside),
      ),
      alignment: Alignment.center,
      child: child,
    );
    return switch (kind) {
      StepKind.done => circle(14, ui.ink, child: MikkyIcon('check', size: 9, color: ui.onInk, stroke: 3.2)),
      StepKind.end => circle(16, ui.green, child: const MikkyIcon('check', size: 10, color: Color(0xFFFFFFFF), stroke: 3.2)),
      StepKind.todo => circle(11, ui.island, ring: ui.track, ringW: 2.5),
      StepKind.it => circle(8, ui.island, ring: ui.text3, ringW: 2),
      StepKind.me => const SizedBox.shrink(),
      StepKind.now => Looping(
        period: const Duration(milliseconds: 2400),
        frozenAt: 1,
        builder: (context, t) {
          final e = const Cubic(.2, .6, .3, 1).transform(t);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.scale(
                scale: 1 + .6 * e,
                child: Opacity(
                  opacity: .45 * (1 - e),
                  child: circle(18, const Color(0x00000000), ring: ui.blue, ringW: 2.5),
                ),
              ),
              circle(18, ui.island, ring: ui.blue, ringW: 3),
            ],
          );
        },
      ),
    };
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.ui, required this.past, required this.now, required this.first, required this.last});

  final MikkyUi ui;
  final bool past, now, first, last;

  @override
  void paint(Canvas canvas, Size size) {
    const x = MetroStep._lineX, w = MetroStep._lineW, dot = MetroStep._dotY;
    final top = first ? dot : 0.0;
    final bottom = last ? dot : size.height;
    if (bottom <= top) return;
    final paint = Paint()..color = past ? ui.ink : ui.track;
    canvas.drawRect(Rect.fromLTRB(x, top, x + w, bottom), paint);
    // The step at work: black down to its dot, grey after.
    if (now && !first) canvas.drawRect(Rect.fromLTRB(x, 0, x + w, dot), Paint()..color = ui.ink);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.ui != ui || old.past != past || old.now != now || old.first != first || old.last != last;
}

/// `.flow`: the blue line creeping down from the step at work (20 → 62 %
/// of the step in 40 s), with a soft halo breathing at its tip (4.2 s).
class _Flow extends StatefulWidget {
  const _Flow();

  @override
  State<_Flow> createState() => _FlowState();
}

class _FlowState extends State<_Flow> {
  // On the DecorClock (30 fps): it moves slowly.
  bool _onClock = false;
  Duration? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  @override
  void dispose() {
    if (_onClock) DecorClock.unlisten(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    var creep = 1.0, halo = 0.0;
    if (_onClock) {
      final now = DecorClock.now.value;
      final s = (now - (_start ??= now)).inMicroseconds / 1e6;
      creep = (s / 40).clamp(0.0, 1.0);
      halo = (1 - math.cos(s / 4.2 * 2 * math.pi)) / 2;
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: _FlowPainter(color: ui.blue, reach: .2 + .42 * const Cubic(.2, .6, .3, 1).transform(creep), halo: halo),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({required this.color, required this.reach, required this.halo});

  final Color color;
  final double reach, halo;

  @override
  void paint(Canvas canvas, Size size) {
    const x = MetroStep._lineX, w = MetroStep._lineW, top = MetroStep._dotY;
    final bottom = top + size.height * reach;
    final line = RRect.fromLTRBR(x, top, x + w, bottom, const Radius.circular(2));
    canvas.drawRRect(
      line,
      Paint()
        ..color = color.withValues(alpha: .3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(line, Paint()..color = color);
    // The halo: 16 px centered on the tip (`bottom: -8px`), 40 % blue
    // fading to nothing at 65 %; it breathes between 25 and 70 % opacity,
    // scale 0.8 to 1.15.
    final center = Offset(x + w / 2, bottom);
    final r = 8 * (.8 + .35 * halo);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: .4 * (.25 + .45 * halo)),
            color.withValues(alpha: 0),
          ],
          stops: const [0, .65],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_FlowPainter old) => old.reach != reach || old.halo != halo || old.color != color;
}
