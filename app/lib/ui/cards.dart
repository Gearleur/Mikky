import 'package:flutter/widgets.dart';

import 'buttons.dart';
import 'feedback.dart';
import 'icons.dart';
import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

/// `.code`: a command in mono, in a small hollow.
class CodePill extends StatelessWidget {
  const CodePill(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: ui.track, borderRadius: BorderRadius.circular(9)),
      child: Text(
        code,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: uiText(12, weight: FontWeight.w500, mono: true, height: 1, color: ui.text),
      ),
    );
  }
}

/// `.group-h`: a home group's title (dot, label, count, chevron); a tap
/// folds or unfolds the group.
class GroupHeader extends StatelessWidget {
  const GroupHeader({super.key, required this.label, required this.color, required this.count, this.open = true, this.onTap, this.first = false});

  final String label;
  final Color color;
  final int count;
  final bool open;
  final VoidCallback? onTap;

  /// The first group sits closer to the head (`padding-top: 4px`).
  final bool first;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final style = uiText(12.5, weight: FontWeight.w600, color: ui.text2, height: 1.2);
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, first ? 4 : 12, 6, 8),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(label, style: style),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: style.copyWith(color: ui.text3, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: open ? 0 : -.25,
                duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 300),
                curve: const Cubic(.34, 1.4, .64, 1),
                child: MikkyIcon('down', size: 14, color: ui.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum AgentCardStyle {
  /// At work: a grey card.
  normal,

  /// Waits for the user: an orange outline, and the question on the card.
  waiting,

  /// Done: a simple outline.
  done,

  /// History: text only, smaller.
  old,
}

/// `.agent`: one agent on the home — state, title, Claude / Codex, what it
/// does now. [actions]: the Oui / Non row of a waiting agent.
class AgentCard extends StatelessWidget {
  const AgentCard({
    super.key,
    required this.status,
    required this.title,
    required this.who,
    this.subtitle,
    this.style = AgentCardStyle.normal,
    this.actions,
    this.onTap,
  });

  final UiStatus status;
  final String title;

  /// Claude, Codex, and where it runs.
  final String who;
  final String? subtitle;
  final AgentCardStyle style;
  final Widget? actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final old = style == AgentCardStyle.old;
    final plain = style == AgentCardStyle.done || old;
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Transform.translate(offset: const Offset(0, -4), child: StatusDot(status)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 20,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: uiText(14, weight: plain ? FontWeight.w500 : FontWeight.w600, color: old ? ui.text2 : ui.text, height: 1.45),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      who,
                      style: uiText(11, weight: FontWeight.w500, color: ui.text3, height: 1.2),
                    ),
                  ],
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: uiText(12.5, color: ui.text2),
                  ),
                ),
              if (actions != null) Padding(padding: const EdgeInsets.only(top: 10), child: actions!),
            ],
          ),
        ),
      ],
    );
    final card = Surface(
      radius: old ? 14 : 18,
      color: plain ? null : ui.well,
      shadows: switch (style) {
        AgentCardStyle.waiting => [CssShadow(0, 0, 0, ui.amber.withValues(alpha: .55), spread: 1.5, inset: true)],
        AgentCardStyle.done => [CssShadow(0, 0, 0, ui.line, spread: 1, inset: true)],
        _ => const [],
      },
      padding: old ? const EdgeInsets.fromLTRB(8, 8, 14, 8) : const EdgeInsets.fromLTRB(8, 12, 14, 12),
      child: body,
    );
    return Pressable(onTap: onTap, pressedScale: .98, child: card);
  }
}

/// The Oui / Non of a waiting agent: the command, then the two buttons.
class WaitActions extends StatelessWidget {
  const WaitActions({super.key, required this.command, this.onYes, this.onNo});

  final String command;
  final VoidCallback? onYes, onNo;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Align(alignment: Alignment.centerLeft, child: CodePill(command)),
      ),
      const SizedBox(width: 6),
      MButton('Non', small: true, onPressed: onNo),
      const SizedBox(width: 6),
      MButton('Oui', small: true, kind: ButtonKind.primary, onPressed: onYes),
    ],
  );
}

/// `.taskcard`: a turn of work in the chat. [live]: the task at work (a
/// grey card that leads back to Suivi); otherwise « Tâche terminée », an
/// outline that unfolds its steps.
class TaskCard extends StatefulWidget {
  const TaskCard({super.key, required this.title, required this.subtitle, this.live = false, this.steps, this.onTap, this.initiallyOpen = false});

  final String title;
  final String subtitle;
  final bool live;
  final Widget? steps;
  final VoidCallback? onTap;
  final bool initiallyOpen;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final head = Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
      child: Row(
        children: [
          StatusDot(widget.live ? UiStatus.working : UiStatus.finished),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(13.5, weight: FontWeight.w600, color: ui.text),
                ),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(12.5, color: ui.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          widget.live
              ? MikkyIcon('right', size: 15, color: ui.text3)
              : AnimatedRotation(
                  turns: _open ? .5 : 0,
                  duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 300),
                  curve: const Cubic(.34, 1.4, .64, 1),
                  child: MikkyIcon('down', size: 15, color: ui.text3),
                ),
        ],
      ),
    );
    if (widget.live) {
      return Pressable(
        onTap: widget.onTap,
        pressedScale: .98,
        child: Surface(radius: 16, color: ui.well, child: head),
      );
    }
    return Surface(
      radius: 16,
      shadows: [CssShadow(0, 0, 0, ui.line, spread: 1, inset: true)],
      child: Column(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => setState(() => _open = !_open), child: head),
          ),
          AnimatedSize(
            duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 320),
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: _open && widget.steps != null
                ? Padding(padding: const EdgeInsets.fromLTRB(10, 0, 12, 4), child: widget.steps)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
