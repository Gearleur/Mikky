import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../side/session_steps.dart';
import '../side/session_views.dart' show stepPalette;
import '../ui/app_glyph.dart';
import '../ui/pixel_fx.dart';
import '../ui/status.dart';
import '../ui/tasks.dart' show TaskStepState;
import '../ui/tokens.dart';

/// The task Mikky looks at in the notch: the latest one at work.
class WatchedTask {
  const WatchedTask({required this.id, required this.name, required this.log, required this.status, this.app});

  final String id;
  final String name;
  final SessionLog log;
  final AgentStatus status;

  /// The software it runs in, if known.
  final AgentApp? app;
}

/// The task's state in a few words, and its color.
(String, Color) _stateOf(WatchedTask task, MikkyUi ui) {
  final log = task.log;
  final turn = log.turns.lastOrNull;
  return switch (task.status) {
    AgentStatus.approval => ('Attend ton feu vert', ui.amber),
    AgentStatus.question => ('Te pose une question', ui.amber),
    AgentStatus.finished => (_finished(log), ui.green),
    AgentStatus.rateLimited => (log.detail, ui.text3),
    AgentStatus.error => ('En erreur', ui.red),
    AgentStatus.idle || AgentStatus.paused => ('Arrêtée', ui.text3),
    _ => (turn != null && turn.plan.isNotEmpty ? 'Au travail · ${planCount(planSteps(turn))}' : 'Au travail', ui.text3),
  };
}

String _finished(SessionLog log) {
  final turn = _worked(log);
  final start = turn == null ? null : turnItems(log, turn).firstOrNull?.at;
  final end = log.lastEventAt;
  if (start == null || end == null) return 'Terminée';
  final m = end.difference(start).inMinutes;
  return 'Terminée · ${m < 1 ? 'moins d’une min' : '$m min'}';
}

/// The latest turn with work in it.
TurnSpan? _worked(SessionLog log) => log.turns.where((t) => t.plan.isNotEmpty || turnItems(log, t).any((i) => i is ToolItem)).lastOrNull;

/// How far the task is in its plan: (steps done, steps); null without one.
(int, int)? progressOf(SessionLog log) {
  final turn = _worked(log);
  if (turn == null || turn.plan.isEmpty) return null;
  final plan = planSteps(turn);
  return (plan.where((s) => s.state == TaskStepState.done).length, plan.length);
}

/// The latest task at a glance (user, 2026-10-05): the software it runs
/// in, its title, its state small and grey with how far it is, then its
/// steps a little indented — the ones that appear and the end, never the
/// messages. No card.
class TaskGlance extends StatelessWidget {
  const TaskGlance({super.key, required this.task, this.steps = 3});

  final WatchedTask task;

  /// Steps shown at most.
  final int steps;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final (state, stateColor) = _stateOf(task, ui);
    final p = progressOf(task.log);
    final app = task.app;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (app != null) ...[AppLine(app), const SizedBox(height: 3)],
        Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.label, weight: FontWeight.w600, color: ui.text)),
        const SizedBox(height: 3),
        Row(children: [
          Flexible(
            child: Text(state, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, weight: FontWeight.w500, color: stateColor, tabular: true)),
          ),
          if (p != null) ...[
            const SizedBox(width: 8),
            TaskProgress(done: p.$1, total: p.$2, color: switch (task.status) {
              AgentStatus.finished => ui.green,
              AgentStatus.approval || AgentStatus.question => ui.amber,
              AgentStatus.rateLimited => ui.yellow,
              AgentStatus.error => ui.red,
              _ => ui.blue,
            }),
          ],
        ]),
        if (steps > 0) ...[
          const SizedBox(height: 5),
          TaskSteps(log: task.log, max: steps, waiting: task.status == AgentStatus.approval || task.status == AgentStatus.question),
        ],
      ],
    );
  }
}

/// How far a task is: one small segment per step of its plan — done, the
/// one at work paler, the ones to come.
class TaskProgress extends StatelessWidget {
  const TaskProgress({super.key, required this.done, required this.total, required this.color});

  final int done, total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Semantics(
      label: '$done sur $total',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < total; i++)
          Container(
            width: 10,
            height: 3,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
            decoration: BoxDecoration(
              color: i < done ? color : (i == done ? color.withValues(alpha: .4) : ui.track),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
      ]),
    );
  }
}

/// A task's steps, a little indented: done (the star of their action),
/// at work (fizzing; amber while it waits for the user), to come.
class TaskSteps extends StatelessWidget {
  const TaskSteps({super.key, required this.log, this.max = 3, this.waiting = false});

  final SessionLog log;
  final int max;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        for (final s in glanceSteps(log, max: max))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              SizedBox(width: 10, child: Center(child: _star(s, ui))),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(
                    TextSize.small,
                    weight: s.state == TaskStepState.now ? FontWeight.w600 : FontWeight.w400,
                    color: switch (s.state) {
                      TaskStepState.now => ui.text,
                      TaskStepState.todo => ui.text3,
                      _ => ui.text2,
                    },
                    height: 1.25,
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _star(MainStep s, MikkyUi ui) => switch (s.state) {
    TaskStepState.now => StatusFx(waiting ? UiStatus.approval : UiStatus.working, size: 10),
    TaskStepState.failed => const PixelStar(PixelFxPalette.red, size: 9),
    TaskStepState.todo => const Opacity(opacity: .35, child: PixelStar(PixelFxPalette.grey, size: 9)),
    TaskStepState.done => PixelStar(stepPalette(s.tone, ui) ?? PixelFxPalette.grey, size: 9),
  };
}
