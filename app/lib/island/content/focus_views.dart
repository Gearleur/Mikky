import 'package:flutter/widgets.dart';

import '../../demo/demo_scene.dart';
import '../../theme.dart';
import 'parts.dart';

/// Answer buttons of the agent in focus.
class FocusActions {
  const FocusActions({required this.onAllow, required this.onDeny});

  final VoidCallback onAllow;
  final VoidCallback onDeny;
}

/// Open island at the top: the "Focus" view of the prototype, to the right
/// of the big Mikky. Laid out at its final size, [width] wide.
class FocusWideView extends StatelessWidget {
  const FocusWideView({super.key, required this.theme, required this.actions, required this.width});

  final MikkyTheme theme;
  final FocusActions actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    const a = DemoScene.focus;
    final others = DemoScene.agents.where((x) => x != a);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              StatusDot(color: t.status(a.color), theme: t),
              const SizedBox(width: 7),
              Text(a.name, style: sansStyle(t, size: 14, weight: FontWeight.w600)),
              const SizedBox(width: 7),
              Text(DemoScene.focusVerb, style: sansStyle(t, color: t.secondary)),
              const Spacer(),
              Text(DemoScene.focusWhen, style: monoStyle(t)),
            ],
          ),
          const SizedBox(height: 9),
          CodeBlock(text: DemoScene.focusCommand, theme: t),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PillButton(label: 'Refuser', theme: t, keyHint: 'N', onTap: actions.onDeny),
              const SizedBox(width: 6),
              PillButton(label: 'Autoriser', theme: t, primary: true, keyHint: 'Y', onTap: actions.onAllow),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final o in others) ...[
                AgentChip(
                  name: o.name,
                  color: t.status(o.color),
                  theme: t,
                  // As in the prototype, only an agent at work shows its progress.
                  value: o.color == StatusColor.working && o.progress != null ? '${(o.progress! * 100).round()}%' : null,
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
/// ([mikkyBottom] is where he ends), then the agent that needs you, its
/// command on several lines, two large buttons, and the list of agents.
class FocusPortraitView extends StatelessWidget {
  const FocusPortraitView({
    super.key,
    required this.theme,
    required this.actions,
    required this.size,
    required this.mikkyBottom,
  });

  final MikkyTheme theme;
  final FocusActions actions;
  final Size size;
  final double mikkyBottom;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    const a = DemoScene.focus;
    final waiting = DemoScene.waitingCount;
    return SizedBox.fromSize(
      size: size,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, mikkyBottom + 14, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Mikky', textAlign: TextAlign.center, style: sansStyle(t, size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              waiting == 1 ? '1 agent attend ton feu vert' : '$waiting agents attendent ton feu vert',
              textAlign: TextAlign.center,
              style: sansStyle(t, size: 12.5, color: t.secondary),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                StatusDot(color: t.status(a.color), theme: t, size: 8),
                const SizedBox(width: 8),
                Expanded(child: Text(a.name, style: sansStyle(t, size: 15, weight: FontWeight.w600))),
                Text(DemoScene.focusWhen, style: monoStyle(t)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 1),
              child: Text(DemoScene.focusVerb, style: sansStyle(t, color: t.secondary)),
            ),
            const SizedBox(height: 10),
            CodeBlock(text: DemoScene.focusCommand, theme: t, maxLines: 4, size: 12.5),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: PillButton(label: 'Refuser', theme: t, keyHint: 'N', height: 40, onTap: actions.onDeny)),
                const SizedBox(width: 8),
                Expanded(
                  child: PillButton(
                    label: 'Autoriser',
                    theme: t,
                    primary: true,
                    keyHint: 'Y',
                    height: 40,
                    onTap: actions.onAllow,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('AGENTS', style: sansStyle(t, size: 11, weight: FontWeight.w600, color: t.secondary).copyWith(letterSpacing: .66)),
                const Spacer(),
                Text('${DemoScene.agents.length} · $waiting en attente', style: monoStyle(t)),
              ],
            ),
            const SizedBox(height: 4),
            for (final (i, agent) in DemoScene.agents.indexed) _AgentRow(agent: agent, theme: t, first: i == 0),
          ],
        ),
      ),
    );
  }
}

/// One line of the agent list (the prototype's "Liste" rows).
class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent, required this.theme, required this.first});

  final DemoAgent agent;
  final MikkyTheme theme;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final color = t.status(agent.color);
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
                    Text(agent.name, style: sansStyle(t, weight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(agent.activity, maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle(t, size: 11.5, weight: FontWeight.w400)),
                    ),
                  ],
                ),
                if (agent.progress != null) ...[
                  const SizedBox(height: 5),
                  ProgressLine(value: agent.progress!, color: color, theme: t),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(agent.time, style: monoStyle(t)),
        ],
      ),
    );
  }
}
