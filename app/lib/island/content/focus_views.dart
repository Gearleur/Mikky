import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../../theme.dart';
import 'focus_model.dart';
import 'parts.dart';

typedef OnAnswer = void Function(Agent agent, AgentAnswer answer);

const _emptyHint = 'Clic droit ▸ Démo pour lancer de faux agents.';

/// Open island at the top: the "Focus" view of the prototype, to the right
/// of the big Mikky. Laid out at its final size, [width] wide.
class FocusWideView extends StatelessWidget {
  const FocusWideView({super.key, required this.text, required this.theme, required this.onAnswer, required this.width});

  final IslandText text;
  final MikkyTheme theme;
  final OnAnswer onAnswer;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final f = text.focus;
    if (f == null || text.content == IslandContent.empty) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.only(top: 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text.header, style: sansStyle(t, size: 14, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_emptyHint, style: sansStyle(t, color: t.secondary)),
            ],
          ),
        ),
      );
    }
    final color = t.status(f.agent.status);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              StatusDot(color: color, theme: t),
              const SizedBox(width: 7),
              // The name only shrinks when the whole line does not fit.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        f.agent.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sansStyle(t, size: 14, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(f.verb, style: sansStyle(t, color: t.secondary)),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(f.when, style: monoStyle(t)),
            ],
          ),
          const SizedBox(height: 9),
          CodeBlock(text: f.detail, theme: t, isError: f.detailIsError),
          const SizedBox(height: 10),
          SizedBox(
            height: 28,
            child: f.actions.isNotEmpty
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final (i, a) in f.actions.indexed) ...[
                        if (i > 0) const SizedBox(width: 6),
                        PillButton(
                          label: a.label,
                          theme: t,
                          primary: a.primary,
                          keyHint: a.keyHint,
                          onTap: () => onAnswer(f.agent, a.answer),
                        ),
                      ],
                    ],
                  )
                : f.progress != null
                    ? Row(
                        children: [
                          Expanded(child: ProgressLine(value: f.progress!, color: color, theme: t, thickness: 3)),
                          const SizedBox(width: 10),
                          Text('${(f.progress! * 100).round()}%', style: monoStyle(t, size: 11.5)),
                        ],
                      )
                    : const SizedBox.shrink(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final o in text.others.take(3)) ...[
                Flexible(
                  child: AgentChip(
                    name: o.agent.name,
                    color: t.status(o.agent.status),
                    theme: t,
                    // As in the prototype, only an agent at work shows its progress.
                    value: o.agent.status == AgentStatus.working && o.progress != null ? '${(o.progress! * 100).round()}%' : null,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Open island on the right: a phone screen in portrait. Mikky sits above
/// ([mikkyBottom] is where he ends), then the agent in focus, its detail on
/// several lines, large buttons, and the list of agents.
class FocusPortraitView extends StatelessWidget {
  const FocusPortraitView({
    super.key,
    required this.text,
    required this.theme,
    required this.onAnswer,
    required this.size,
    required this.mikkyBottom,
  });

  final IslandText text;
  final MikkyTheme theme;
  final OnAnswer onAnswer;
  final Size size;
  final double mikkyBottom;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final f = text.focus;
    final empty = f == null || text.content == IslandContent.empty;
    return SizedBox.fromSize(
      size: size,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, mikkyBottom + 14, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Mikky', textAlign: TextAlign.center, style: sansStyle(t, size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(text.header, textAlign: TextAlign.center, style: sansStyle(t, size: 12.5, color: t.secondary)),
            if (empty) ...[
              const SizedBox(height: 40),
              Text(_emptyHint, textAlign: TextAlign.center, style: sansStyle(t, color: t.secondary)),
            ] else ...[
              const SizedBox(height: 22),
              ..._focus(t, f),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text('AGENTS', style: sansStyle(t, size: 11, weight: FontWeight.w600, color: t.secondary).copyWith(letterSpacing: .66)),
                  const Spacer(),
                  Text(
                    text.all.length == 1 ? '1 agent' : '${text.all.length} agents',
                    style: monoStyle(t),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final (i, a) in text.all.take(5).indexed) _AgentRow(text: a, theme: t, first: i == 0),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _focus(MikkyTheme t, AgentText f) {
    final color = t.status(f.agent.status);
    return [
      Row(
        children: [
          StatusDot(color: color, theme: t, size: 8),
          const SizedBox(width: 8),
          Expanded(child: Text(f.agent.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sansStyle(t, size: 15, weight: FontWeight.w600))),
          Text(f.when, style: monoStyle(t)),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: 16, top: 1),
        child: Text(f.verb, style: sansStyle(t, color: t.secondary)),
      ),
      const SizedBox(height: 10),
      CodeBlock(text: f.detail, theme: t, isError: f.detailIsError, maxLines: 4, size: 12.5),
      const SizedBox(height: 12),
      SizedBox(
        height: 40,
        child: f.actions.isNotEmpty
            ? Row(
                children: [
                  for (final (i, a) in f.actions.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: PillButton(
                        label: a.label,
                        theme: t,
                        primary: a.primary,
                        keyHint: a.keyHint,
                        height: 40,
                        onTap: () => onAnswer(f.agent, a.answer),
                      ),
                    ),
                  ],
                ],
              )
            : f.progress != null
                ? Row(
                    children: [
                      Expanded(child: ProgressLine(value: f.progress!, color: color, theme: t, thickness: 3)),
                      const SizedBox(width: 10),
                      Text('${(f.progress! * 100).round()}%', style: monoStyle(t, size: 11.5)),
                    ],
                  )
                : const SizedBox.shrink(),
      ),
    ];
  }
}

/// One line of the agent list (the prototype's "Liste" rows).
class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.text, required this.theme, required this.first});

  final AgentText text;
  final MikkyTheme theme;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final a = text.agent;
    final color = t.status(a.status);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: t.faint))),
      child: Row(
        children: [
          StatusDot(color: color, theme: t, glowRadius: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sansStyle(t, weight: FontWeight.w600))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text.listActivity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(t, size: 11.5, weight: FontWeight.w400),
                      ),
                    ),
                  ],
                ),
                if (text.progress != null) ...[
                  const SizedBox(height: 5),
                  ProgressLine(value: text.progress!, color: color, theme: t),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(text.listTime, style: monoStyle(t)),
        ],
      ),
    );
  }
}
