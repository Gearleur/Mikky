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
              IslandDot(color: color, theme: t),
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
