import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'motion.dart';
import 'pixel_fx.dart';
import 'sliding_hover.dart';
import 'status.dart';
import 'tokens.dart';

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
    duration: Motion.of(context, Motion.fold),
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
        const SizedBox(width: 7),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: widget.title, style: uiText(TextSize.label, weight: FontWeight.w600, color: ui.text)),
              if (widget.meta != null) TextSpan(text: '  ${widget.meta}', style: uiText(TextSize.small, color: ui.text3, tabular: true)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.action != null)
          HoverRow(
            onTap: widget.onAction,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(widget.action!, style: uiText(TextSize.small, weight: FontWeight.w500, color: ui.blue)),
          ),
        if (foldable) ...[
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: _open ? .5 : 0,
            duration: Motion.of(context, Motion.fold),
            curve: const Cubic(.34, 1.4, .64, 1),
            child: MikkyIcon('down', size: 14, color: ui.text3),
          ),
        ],
      ],
    );
    // The sliding square of the Oui / Non answers as hover (user request,
    // 2026-09-30).
    return SlidingHover(
      radius: Radii.md,
      child: Column(
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
                        child: Text(_details ? 'Masquer le détail' : 'Voir le détail', style: uiText(TextSize.small, weight: FontWeight.w500, color: ui.text3)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How a main step of a task went.
enum TaskStepState { done, now, todo, failed }

/// A main step of a task: a dot and a few words (« Lit 3 fichiers »). A
/// tap unfolds [detail], what the agent did for it.
class TaskStep extends StatefulWidget {
  const TaskStep({super.key, required this.label, this.state = TaskStepState.done, this.note, this.detail, this.tone, this.initiallyOpen = false});

  final String label;
  final TaskStepState state;

  /// The star's colors for what the step does (green creates, blue
  /// changes, orange runs a command…); grey when not given.
  final PixelFxPalette? tone;

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
    final (star, text) = switch (widget.state) {
      TaskStepState.done => (widget.tone ?? PixelFxPalette.grey, ui.text2),
      TaskStepState.now => (PixelFxPalette.blue, ui.text),
      TaskStepState.todo => (PixelFxPalette.grey, ui.text3),
      TaskStepState.failed => (PixelFxPalette.red, ui.text2),
    };
    final row = Row(
      children: [
        // A small still star of the action's color (user request,
        // 2026-09-30); the step at work fizzes; the ones to come are faint.
        SizedBox(
          width: 11,
          child: Center(
            child: widget.state == TaskStepState.now
                ? const StatusFx(UiStatus.working, size: 11)
                : Opacity(opacity: widget.state == TaskStepState.todo ? .35 : 1, child: PixelStar(star, size: 11)),
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
            style: uiText(TextSize.label, weight: widget.state == TaskStepState.now ? FontWeight.w600 : FontWeight.w400, color: text, height: 1.35),
          ),
        ),
        if (widget.detail != null)
          AnimatedRotation(
            turns: _open ? .5 : 0,
            duration: Motion.of(context, Motion.fold),
            child: MikkyIcon('down', size: 12, color: ui.text3),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoverRow(onTap: widget.detail == null ? null : () => setState(() => _open = !_open), child: row),
        AnimatedSize(
          duration: Motion.of(context, Motion.fold),
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
              Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: uiText(TextSize.small, color: ui.text, height: 1.35)),
              if (widget.detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(widget.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, mono: true, color: ui.text3, height: 1.4)),
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
          duration: Motion.of(context, Motion.fold),
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
      style: uiText(thought ? TextSize.small : TextSize.label, color: thought ? ui.text3 : ui.text2, height: 1.4),
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
      decoration: BoxDecoration(color: ui.well, borderRadius: BorderRadius.circular(Radii.md)),
      child: Text(
        [if (all.length > lines) '…', ...shown].join('\n'),
        style: uiText(TextSize.code, mono: true, color: ui.text2, height: 1.45),
      ),
    );
  }
}
