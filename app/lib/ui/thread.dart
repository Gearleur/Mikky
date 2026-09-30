import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'feedback.dart';
import 'icons.dart';
import 'markdown.dart';
import 'motion.dart';
import 'pixel_fx.dart';
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

/// A chat bubble (`.msg`, `.bub`): the user's in ink on the right, the
/// agent's grey on the left; the corner towards the speaker is sharper.
class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.me, required this.child, this.thread = false});

  final bool me;
  final Widget child;

  /// In the metro line the agent's corner is at the top (`.msg-it .bub`).
  final bool thread;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    const big = Radius.circular(20), small = Radius.circular(8);
    final radius = me
        ? const BorderRadius.only(topLeft: big, topRight: big, bottomLeft: big, bottomRight: small)
        : (thread
              ? const BorderRadius.only(topLeft: small, topRight: big, bottomLeft: big, bottomRight: big)
              : const BorderRadius.only(topLeft: big, topRight: big, bottomLeft: small, bottomRight: big));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(color: me ? ui.ink : ui.well, borderRadius: radius),
      child: DefaultTextStyle(
        style: uiText(14, color: me ? ui.onInk : ui.text, height: 1.4),
        child: child,
      ),
    );
  }
}

/// A chat message with its line of meta (`.msg` + `.mmeta`). The user's
/// is a bubble, 84 % wide at most; the agent's has no bubble and takes the
/// whole width, as chat apps do (user request, 2026-09-30).
class ChatMessage extends StatelessWidget {
  const ChatMessage({super.key, required this.me, required this.text, this.meta});

  final bool me;
  final String text;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final metaLine = meta == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Text(meta!, style: uiText(11, color: ui.text3, height: 1.3)),
          );
    if (!me) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 2, 2, 2),
            child: DefaultTextStyle(style: uiText(14, color: ui.text, height: 1.5), child: AgentText(text)),
          ),
          ?metaLine,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FractionallySizedBox(
          widthFactor: .84,
          alignment: Alignment.centerRight,
          child: Align(alignment: Alignment.centerRight, child: Bubble(me: true, child: Text(text))),
        ),
        ?metaLine,
      ],
    );
  }
}

/// Something to click in the chat: a light grey under the mouse, the
/// hand cursor (user request, 2026-09-30).
class HoverRow extends StatefulWidget {
  const HoverRow({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4)});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    if (widget.onTap == null) return Padding(padding: widget.padding, child: widget.child);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: widget.padding,
          decoration: BoxDecoration(color: _hover ? ui.hover : ui.hover.withValues(alpha: 0), borderRadius: BorderRadius.circular(9)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A task in the chat, part of the page (no card): its state in pixels,
/// its title and figures, a chevron. Open: its main steps, as dots; under
/// them « Voir le détail » shows [details], everything the agent did (user
/// requests, 2026-09-30). [action]: a link on the right (« Suivi » while
/// it works).
class TaskSection extends StatefulWidget {
  const TaskSection({
    super.key,
    required this.status,
    required this.title,
    this.meta,
    this.steps = const [],
    this.details = const [],
    this.initiallyOpen = false,
    this.initiallyDetails = false,
    this.action,
    this.onAction,
  });

  final UiStatus status;
  final String title;
  final String? meta;

  /// The main steps ([TaskStep]).
  final List<Widget> steps;

  /// Everything, shown on demand.
  final List<Widget> details;
  final bool initiallyOpen;

  /// The detail shown from the start (boards).
  final bool initiallyDetails;
  final String? action;
  final VoidCallback? onAction;

  @override
  State<TaskSection> createState() => _TaskSectionState();
}

class _TaskSectionState extends State<TaskSection> {
  late bool _open = widget.initiallyOpen;
  late bool _details = widget.initiallyDetails;

  Widget _fold(BuildContext context, bool open, Widget child) => AnimatedSize(
    duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 320),
    curve: Motion.enter,
    alignment: Alignment.topCenter,
    child: open ? child : const SizedBox(width: double.infinity),
  );

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final foldable = widget.steps.isNotEmpty || widget.details.isNotEmpty;
    final head = Row(
      children: [
        StatusFx(widget.status, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: widget.title, style: uiText(13.5, weight: FontWeight.w600, color: ui.text)),
              if (widget.meta != null) TextSpan(text: '  ${widget.meta}', style: uiText(12.5, color: ui.text3, tabular: true)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.action != null)
          HoverRow(
            onTap: widget.onAction,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(widget.action!, style: uiText(12.5, weight: FontWeight.w500, color: ui.blue)),
          ),
        if (foldable) ...[
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: _open ? .5 : 0,
            duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 300),
            curve: const Cubic(.34, 1.4, .64, 1),
            child: MikkyIcon('down', size: 14, color: ui.text3),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Level with the text of the messages: the hover grey reaches out a
        // little on the left instead of pushing the row right.
        Transform.translate(
          offset: const Offset(-4, 0),
          child: HoverRow(
            onTap: foldable ? () => setState(() => _open = !_open) : null,
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: head,
          ),
        ),
        _fold(
          context,
          _open && foldable,
          Container(
            margin: const EdgeInsets.only(left: 6, bottom: 4),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: ui.line, width: 1.5))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...widget.steps,
                if (widget.details.isNotEmpty) ...[
                  _fold(
                    context,
                    _details,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 0, 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < widget.details.length; i++)
                            Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 8), child: widget.details[i]),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: HoverRow(
                      onTap: () => setState(() => _details = !_details),
                      child: Text(_details ? 'Masquer le détail' : 'Voir le détail', style: uiText(12, weight: FontWeight.w500, color: ui.text3)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// How a main step of a task went.
enum TaskStepState { done, now, todo, failed }

/// A main step of a task: a dot and a few words (« Lit 3 fichiers »). A
/// tap unfolds [detail], what the agent did for it.
class TaskStep extends StatefulWidget {
  const TaskStep({super.key, required this.label, this.state = TaskStepState.done, this.note, this.detail, this.color, this.initiallyOpen = false});

  final String label;
  final TaskStepState state;

  /// The dot's color for what the step does (green creates, blue changes,
  /// orange runs a command…); grey when not given.
  final Color? color;

  /// [detail] shown from the start (boards).
  final bool initiallyOpen;

  /// In red after the label: « refusé », « échec ».
  final String? note;
  final Widget? detail;

  @override
  State<TaskStep> createState() => _TaskStepState();
}

class _TaskStepState extends State<TaskStep> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final (dot, text) = switch (widget.state) {
      TaskStepState.done => (widget.color ?? ui.text3, ui.text2),
      TaskStepState.now => (ui.blue, ui.text),
      TaskStepState.todo => (ui.track, ui.text3),
      TaskStepState.failed => (ui.red, ui.text2),
    };
    final row = Row(
      children: [
        // A pixel of the action's color; the step at work fizzes.
        SizedBox(
          width: 10,
          child: Center(
            child: widget.state == TaskStepState.now
                ? const StatusFx(UiStatus.working, size: 10)
                : Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(1.5))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: widget.label),
              if (widget.note != null) TextSpan(text: ' · ${widget.note}', style: TextStyle(color: ui.red, fontWeight: FontWeight.w500)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: uiText(13, weight: widget.state == TaskStepState.now ? FontWeight.w600 : FontWeight.w400, color: text, height: 1.35),
          ),
        ),
        if (widget.detail != null)
          AnimatedRotation(
            turns: _open ? .5 : 0,
            duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 260),
            child: MikkyIcon('down', size: 12, color: ui.text3),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoverRow(onTap: widget.detail == null ? null : () => setState(() => _open = !_open), child: row),
        AnimatedSize(
          duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 260),
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: _open && widget.detail != null
              ? Padding(padding: const EdgeInsets.fromLTRB(22, 2, 0, 6), child: widget.detail)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// One thing the agent did, in the detail of a task: an icon, what, and in
/// mono the command or the file; on the right its state. A tap unfolds
/// [body] (the code it changed, what the command printed).
class ToolLine extends StatefulWidget {
  const ToolLine({super.key, required this.icon, required this.title, this.detail, this.trailing, this.body, this.initiallyOpen = false});

  /// [body] shown from the start (boards).
  final bool initiallyOpen;
  final String icon;
  final String title;
  final String? detail;
  final Widget? trailing;
  final Widget? body;

  @override
  State<ToolLine> createState() => _ToolLineState();
}

class _ToolLineState extends State<ToolLine> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: MikkyIcon(widget.icon, size: 14, color: ui.text3)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: uiText(12.5, color: ui.text, height: 1.35)),
              if (widget.detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(widget.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(11, mono: true, color: ui.text3, height: 1.4)),
                ),
            ],
          ),
        ),
        if (widget.trailing != null) Padding(padding: const EdgeInsets.only(left: 8, top: 1), child: widget.trailing!),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoverRow(onTap: widget.body == null ? null : () => setState(() => _open = !_open), child: row),
        AnimatedSize(
          duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 260),
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: _open && widget.body != null
              ? Padding(padding: const EdgeInsets.only(left: 28, top: 4, right: 4), child: widget.body)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// A line of the agent's own words in a task: what it thought (grey,
/// short), or what it said on the way.
class NoteLine extends StatelessWidget {
  const NoteLine(this.text, {super.key, this.thought = false});

  final String text;
  final bool thought;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Text(
      // Short and plain: no markdown marks.
      text.replaceAll(RegExp(r'\*\*|__|`'), ''),
      maxLines: thought ? 2 : 4,
      overflow: TextOverflow.ellipsis,
      style: uiText(thought ? 12.5 : 13, color: thought ? ui.text3 : ui.text2, height: 1.4),
    );
  }
}

/// What a command printed, its last lines, in mono, in a light hollow.
class OutputBox extends StatelessWidget {
  const OutputBox(this.text, {super.key, this.lines = 12});

  final String text;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final all = text.trimRight().split('\n');
    final shown = all.length > lines ? all.sublist(all.length - lines) : all;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: ui.well, borderRadius: BorderRadius.circular(10)),
      child: Text(
        [if (all.length > lines) '…', ...shown].join('\n'),
        style: uiText(10.5, mono: true, color: ui.text2, height: 1.45),
      ),
    );
  }
}

/// One line of a [CodeCard]: its number, its text (spans for colors), and
/// whether it was removed or added.
class CodeLine {
  const CodeLine(this.number, this.spans, {this.removed = false, this.added = false});

  final int number;
  final List<InlineSpan> spans;
  final bool removed, added;
}

/// `.codecard`: the code the agent writes, live, under the step at work:
/// the file's name, then the changed lines (red removed, green added).
class CodeCard extends StatelessWidget {
  const CodeCard({super.key, required this.file, required this.lines});

  final String file;
  final List<CodeLine> lines;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final mono = uiText(10.5, mono: true, color: ui.text, height: 18 / 10.5);
    return Container(
      decoration: BoxDecoration(
        color: ui.well,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ui.line, strokeAlign: BorderSide.strokeAlignInside),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: ui.line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: ui.amber, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  file,
                  style: uiText(10.5, mono: true, weight: FontWeight.w500, color: ui.text2, height: 1.2),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final l in lines)
                  Container(
                    decoration: BoxDecoration(
                      color: l.removed ? ui.red.withValues(alpha: .1) : (l.added ? ui.green.withValues(alpha: .12) : null),
                      border: l.removed || l.added ? Border(left: BorderSide(color: l.removed ? ui.red : ui.green, width: 2)) : null,
                    ),
                    padding: EdgeInsets.only(right: 8, left: l.removed || l.added ? 0 : 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${l.number}',
                            textAlign: TextAlign.right,
                            style: mono.copyWith(color: ui.text3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: l.spans),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: l.removed ? mono.copyWith(color: ui.text2, decoration: TextDecoration.lineThrough) : mono,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
