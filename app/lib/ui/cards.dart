import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'brand_logo.dart';
import 'feedback.dart';
import 'icons.dart';
import 'motion.dart';
import 'pixel_fx.dart';
import 'sliding_hover.dart';
import 'status.dart';
import 'surface.dart';
import 'tokens.dart';

/// `.code`: a command in mono, in a small hollow.
class CodePill extends StatelessWidget {
  const CodePill(this.code, {super.key, this.maxLines = 1});

  final String code;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    // In a hollow, so it shows on the raised grey cards too.
    return Surface(
      radius: Radii.md,
      color: ui.track,
      shadows: ui.inset,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        code,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: uiText(TextSize.small, weight: FontWeight.w500, mono: true, height: maxLines > 1 ? 1.35 : 1, color: ui.text),
      ),
    );
  }
}

enum AgentCardStyle {
  /// At work: a grey card.
  normal,

  /// Waits for the user: an orange outline, and the question on the card.
  waiting,

  /// Done: a plain row, like a directory listing — the tool's logo, the
  /// title, and when on the right (user request, 2026-09-30).
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
    this.onMenu,
    this.pinned = false,
    this.brand,
    this.mark,
  });

  /// A small sign right after the title: the yellow star of a limit, the
  /// violet one of a spell.
  final Widget? mark;

  final UiStatus status;
  final String title;

  /// Claude, Codex, and where it runs.
  final String who;
  final String? subtitle;
  final AgentCardStyle style;
  final Widget? actions;
  final VoidCallback? onTap;

  /// A right click: what to do with this session.
  final VoidCallback? onMenu;

  /// Kept at the top of its group: a small pin before [who].
  final bool pinned;

  /// The tool's logo, before [who].
  final Brand? brand;

  @override
  Widget build(BuildContext context) {
    if (style == AgentCardStyle.done) return _doneRow(context);
    final ui = MikkyUi.of(context);
    final old = style == AgentCardStyle.old;
    final plain = style == AgentCardStyle.done || old;
    // At work or waiting: the tool's logo, and the dots lit in the state's
    // color (user request, 2026-09-30). History keeps its dot.
    final live = !plain && brand != null;
    final titleRow = SizedBox(
      height: 20,
      child: Row(
        children: [
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(TextSize.body, weight: plain ? FontWeight.w500 : FontWeight.w600, color: old ? ui.text2 : ui.text, height: 1.45),
                ),
              ),
              if (mark != null) ...[const SizedBox(width: 6), mark!],
            ]),
          ),
          const SizedBox(width: 8),
          if (pinned) ...[MikkyIcon('pin', size: 12, color: ui.text3), const SizedBox(width: 3)],
          if (brand != null && !live) ...[BrandLogo(brand!, size: 12), const SizedBox(width: 4)],
          if (who.isNotEmpty)
            Text(
              who,
              style: uiText(TextSize.caption, weight: FontWeight.w500, color: ui.text3, height: 1.2),
            ),
          if (!live) ?_menuStar(),
        ],
      ),
    );
    final subtitleText = subtitle == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: uiText(TextSize.small, color: ui.text2),
            ),
          );
    final Widget body;
    if (live) {
      // At work or waiting (user request, 2026-09-30): the tool's logo,
      // level with the two lines (24 px since the same day: « trop gros »);
      // it turns while the agent works and hops now and then while it
      // waits. Oui / Non below, under the text.
      final logo = BrandLogo(brand!, size: 24);
      final head = Row(
        children: [
          SizedBox(
            width: 28,
            child: Center(
              child: switch (status) {
                UiStatus.working => SpinningLogo(claude: brand == Brand.claude, child: logo),
                UiStatus.approval => Looping(
                  period: const Duration(milliseconds: 1800),
                  builder: (context, t) => Transform.translate(offset: Offset(0, -4 * StatusDot.hop(t)), child: logo),
                ),
                _ => logo,
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleRow, ?subtitleText],
            ),
          ),
          ?_menuStar(),
        ],
      );
      body = actions == null
          ? head
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [head, Padding(padding: const EdgeInsets.only(left: 38, top: 8), child: actions!)],
            );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(offset: const Offset(0, -4), child: StatusDot(status)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleRow,
                ?subtitleText,
                if (actions != null) Padding(padding: const EdgeInsets.only(top: 10), child: actions!),
              ],
            ),
          ),
        ],
      );
    }
    // At work or waiting: no card, a plain row (user request,
    // 2026-09-30). Without a logo (the Oui / Non of an agent's page): the
    // grey card with the orange outline, as before.
    final waiting = style == AgentCardStyle.waiting;
    final card = Surface(
      radius: old ? Radii.lg : Radii.xl,
      color: plain || live ? null : ui.well,
      shadows: [
        if (waiting && !live) ui.waitRing,
      ],
      padding: old
          ? const EdgeInsets.fromLTRB(8, 8, 14, 8)
          : live
          ? const EdgeInsets.fromLTRB(6, 8, 14, 8)
          : const EdgeInsets.fromLTRB(8, 12, 14, 12),
      child: body,
    );
    return _pressable(card);
  }

  Widget _pressable(Widget card) {
    // In a list with the sliding square (the home), the square shows the
    // hover; alone, a light grey under the mouse.
    final hovered = Builder(
      builder: (context) => SlidingHover.maybeOf(context) != null && onTap != null
          ? HoverTarget(child: card)
          : HoverBuilder(
              enabled: onTap != null,
              builder: (context, hover) {
                final ui = MikkyUi.of(context);
                return AnimatedContainer(
                  duration: Motion.hover,
                  decoration: BoxDecoration(color: hover ? ui.hover : ui.hover.withValues(alpha: 0), borderRadius: BorderRadius.circular(Radii.lg)),
                  child: card,
                );
              },
            ),
    );
    final pressable = Pressable(onTap: onTap, pressedScale: .98, child: hovered);
    return onMenu == null ? pressable : GestureDetector(onSecondaryTap: onMenu, child: pressable);
  }

  /// One line: logo, title, then pin, [subtitle] (when) and
  /// [who] (where) on the right.
  Widget _doneRow(BuildContext context) {
    final ui = MikkyUi.of(context);
    final side = [if (subtitle != null && subtitle!.isNotEmpty) subtitle!, if (who.isNotEmpty) who].join(' · ');
    return _pressable(Surface(
      radius: Radii.lg,
      padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: Center(child: brand == null ? StatusDot(status) : BrandLogo(brand!, size: 18)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: uiText(TextSize.body, weight: FontWeight.w500, color: ui.text, height: 1.3),
            ),
          ),
          const SizedBox(width: 8),
          if (pinned) ...[MikkyIcon('pin', size: 12, color: ui.text3), const SizedBox(width: 4)],
          Text(side, style: uiText(TextSize.caption, color: ui.text3, height: 1.2, tabular: true)),
          ?_menuStar(),
        ],
      ),
    ));
  }

  /// A small grey star on the right: the same menu as a right click
  /// (pause, reprendre, arrêter, ranger…) without opening the agent (user
  /// request, 2026-09-30).
  Widget? _menuStar() => onMenu == null ? null : Padding(padding: const EdgeInsets.only(left: 6), child: MenuStar(onTap: onMenu!));
}

/// The Oui / Non of a waiting agent: the command, then the answers in a
/// small flat bar (user request, 2026-09-30: the raised buttons stood out
/// too much and took too much room).
class WaitActions extends StatelessWidget {
  const WaitActions({super.key, required this.command, this.onYes, this.onNo, this.onAlways});

  final String command;
  final VoidCallback? onYes, onNo, onAlways;

  /// Longer than this, the command gets a line of its own (up to three),
  /// above the answers: the user must read what they say yes to.
  static const shortCommand = 18;

  @override
  Widget build(BuildContext context) {
    final bar = AnswerBar(answers: [
      if (onAlways != null) ('Toujours', onAlways),
      ('Non', onNo),
      ('Oui', onYes),
    ]);
    if (command.length <= shortCommand && onAlways == null) {
      return Row(
        children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: CodePill(command))),
          const SizedBox(width: 8),
          bar,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CodePill(command, maxLines: 3),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: bar),
      ],
    );
  }
}

/// A few answers side by side, in nothing: the chosen one sits on a white
/// square with a soft shadow, the main one (the last) at first. Pressing
/// another slides the square to it, with the selectors' spring, then the
/// answer goes on release (user request, 2026-09-30).
class AnswerBar extends StatefulWidget {
  const AnswerBar({super.key, required this.answers});

  final List<(String, VoidCallback?)> answers;

  static const height = 28.0, padX = 13.0, gap = 2.0;

  @override
  State<AnswerBar> createState() => _AnswerBarState();
}

class _AnswerBarState extends State<AnswerBar> {
  late int _on = widget.answers.length - 1;
  int? _hover;

  @override
  void didUpdateWidget(AnswerBar old) {
    super.didUpdateWidget(old);
    if (old.answers.length != widget.answers.length) _on = widget.answers.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final style = uiText(TextSize.label, weight: FontWeight.w600, height: 1);
    final widths = [for (final (label, _) in widget.answers) _textWidth(label, style, scaler) + AnswerBar.padX * 2];
    final lefts = <double>[];
    var x = 0.0;
    for (final w in widths) {
      lefts.add(x);
      x += w + AnswerBar.gap;
    }
    final n = widths.length;
    return SizedBox(
      width: x - AnswerBar.gap,
      height: AnswerBar.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: SpringValue(
                target: _on.toDouble(),
                spring: Motion.thumb,
                builder: (context, at, v) {
                  // Between two answers: the square takes a bit of both.
                  final i0 = at.floor().clamp(0, n - 1), i1 = (i0 + 1).clamp(0, n - 1);
                  final f = (at - i0).clamp(0.0, 1.0);
                  final left = lefts[i0] + (lefts[i1] - lefts[i0]) * f;
                  final width = widths[i0] + (widths[i1] - widths[i0]) * f;
                  // Stretched by its speed, like the selectors' thumb.
                  final stretch = (v.abs() * 55 * Motion.thumbStretch).clamp(0.0, 8.0);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: left - (v < 0 ? stretch : 0),
                        top: 0,
                        bottom: 0,
                        width: width + stretch,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: ui.thumb,
                            borderRadius: BorderRadius.circular(Radii.md),
                            // A hairline, so the white shows on the white window too.
                            border: Border.all(color: ui.line, width: .8),
                            boxShadow: [
                              for (final s in ui.shThumb)
                                if (!s.inset) s.box,
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: AnswerBar.gap),
                _answer(ui, i, widths[i], style),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _answer(MikkyUi ui, int i, double width, TextStyle style) {
    final (label, onTap) = widget.answers[i];
    final on = onTap != null;
    final hovered = _hover == i && i != _on;
    return Opacity(
      opacity: on ? 1 : .35,
      child: MouseRegion(
        cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = i),
        onExit: (_) => setState(() => _hover = null),
        child: Listener(
          // The square leaves on press; the answer goes on release.
          onPointerDown: on ? (e) => e.buttons == kPrimaryButton ? setState(() => _on = i) : null : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.hover,
              width: width,
              height: AnswerBar.height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hovered ? ui.hover : ui.hover.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: AnimatedDefaultTextStyle(
                duration: Motion.fade,
                style: style.copyWith(color: i == _on || hovered ? ui.text : ui.text2),
                child: Text(label, maxLines: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final Map<(String, double), double> _answerWidths = {};

double _textWidth(String text, TextStyle style, TextScaler scaler) => _answerWidths[(text, scaler.scale(1))] ??= () {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler)..layout();
  final w = tp.width.ceilToDouble();
  tp.dispose();
  return w;
}();

/// A grey pixel star to press: opens a menu. Not seen until the mouse is
/// right on it (user request, 2026-09-30: « pas apparente, qu'on soit
/// vraiment proche »); a 24 px target around it.
class MenuStar extends StatelessWidget {
  const MenuStar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: HoverBuilder(
            builder: (context, hover) => SizedBox.square(
              dimension: 24,
              child: Center(
                child: AnimatedOpacity(
                  duration: Motion.hover,
                  opacity: hover ? 1 : 0,
                  child: const PixelStar(PixelFxPalette.grey, size: 10),
                ),
              ),
            ),
          ),
        ),
      );
}
