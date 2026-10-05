import 'package:mikky_engine/mikky_engine.dart';

import '../ui/status.dart';
import '../ui/tasks.dart' show TaskStepState;
import 'session_text.dart';

// How a session becomes its thread, before any widget: each turn's task,
// what happened in it in order (the agent's words, its actions grouped in
// main steps), and its answer. Pure, testable without a screen;
// `session_views.dart` draws it.

/// The items of a turn.
List<ThreadItem> turnItems(SessionLog log, TurnSpan turn) => log.items.sublist(turn.start, turn.end ?? log.items.length);

/// The agent offers « always allow » for its pending request.
bool canAlways(SessionLog log) => log.pending.firstOrNull?.options.any((o) => o.kind == 'allow_always') ?? false;

/// What a tool is called, as the agent names it.
String toolTitle(ToolItem t) => t.title.isEmpty ? (t.name ?? 'Outil') : t.title;

/// The command or the file of a tool, when it says more than its title.
String? toolDetail(ToolItem t) {
  final raw = t.command ?? t.path;
  return raw == null || raw.trim() == toolTitle(t).trim() ? null : raw;
}

/// In red after a failed tool: « refusé » (the user said no), « échec ».
String? toolNote(ToolItem t) {
  if (t.status != ToolStatus.failed) return null;
  final out = (t.output ?? '').toLowerCase();
  return out.contains('refused') || out.contains('rejected') || out.contains('denied') ? 'refusé' : 'échec';
}

/// Lines added and removed by a change (blank lines left out).
({int added, int removed}) diffCounts(FileDiff diff) => (
  added: diff.newText.split('\n').where((l) => l.trim().isNotEmpty).length,
  removed: (diff.oldText ?? '').split('\n').where((l) => l.trim().isNotEmpty).length,
);

/// The few lines of a change shown under the step at work: up to two
/// removed, then the first added (five when nothing was removed).
({List<String> removed, List<String> added}) diffPreview(FileDiff diff) {
  final removed = (diff.oldText ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(2).toList();
  final added = diff.newText.split('\n').take(removed.isEmpty ? 5 : 3).toList();
  return (removed: removed, added: added);
}

// --------------------------------------------------------------- Steps

/// What an important action is, for the color of its step's star (user
/// request, 2026-09-30); reading and searching have none (grey).
enum StepTone {
  /// A step of the agent's plan.
  plan,
  created,
  changed,
  deleted,
  moved,
  ran,
  web,
}

/// A main step of a task: its plan's step, or tools of one kind in a row
/// (« Lit 3 fichiers »).
class MainStep {
  const MainStep({required this.label, required this.state, this.tone, this.note, this.tools = const []});

  final String label;
  final TaskStepState state;
  final StepTone? tone;
  final String? note;

  /// The tools it gathers; none for a plan's step.
  final List<ToolItem> tools;
}

/// What kind of main step a tool belongs to: tools of the same kind in a
/// row make one step (« Lit 3 fichiers »). Null: not worth a step (the
/// agent's own bookkeeping, like loading its tools or its to-do list).
String? _groupOf(ToolItem t) => switch (t.kind) {
  ToolKind.read || ToolKind.search => 'look',
  ToolKind.edit => 'edit:${t.path ?? t.id}',
  ToolKind.delete => 'delete:${t.id}',
  ToolKind.move => 'move:${t.id}',
  ToolKind.execute => 'run',
  ToolKind.fetch => 'web',
  ToolKind.think => null,
  ToolKind.other => t.status == ToolStatus.failed ? 'other:${t.id}' : null,
};

/// A main step in a few words, for tools of one group.
String stepLabel(List<ToolItem> tools) {
  final t = tools.first;
  final n = tools.length;
  String name(ToolItem t) => folderName(t.path ?? t.diff?.path);
  switch (t.kind) {
    case ToolKind.read || ToolKind.search:
      final reads = tools.where((t) => t.kind == ToolKind.read).length;
      if (reads == n) return n == 1 && name(t).isNotEmpty ? 'Lit ${name(t)}' : 'Lit $n fichiers';
      if (reads == 0) return n == 1 ? 'Cherche dans le code' : 'Cherche dans le code ($n fois)';
      return 'Explore le code ($n)';
    case ToolKind.edit:
      final created = t.diff != null && t.diff!.oldText == null;
      final file = name(t).isEmpty ? 'un fichier' : name(t);
      return '${created ? 'Crée' : 'Modifie'} $file';
    case ToolKind.delete:
      return 'Supprime ${name(t).isEmpty ? 'un fichier' : name(t)}';
    case ToolKind.move:
      return 'Déplace ${name(t).isEmpty ? 'un fichier' : name(t)}';
    case ToolKind.execute:
      return n == 1 ? 'Lance une commande' : 'Lance $n commandes';
    case ToolKind.fetch:
      return n == 1 ? 'Va sur internet' : 'Va sur internet ($n fois)';
    case ToolKind.think || ToolKind.other:
      return toolTitle(t);
  }
}

StepTone? _toneOf(List<ToolItem> tools) {
  final t = tools.first;
  return switch (t.kind) {
    ToolKind.edit => t.diff != null && t.diff!.oldText == null ? StepTone.created : StepTone.changed,
    ToolKind.delete => StepTone.deleted,
    ToolKind.move => StepTone.moved,
    ToolKind.execute => StepTone.ran,
    ToolKind.fetch => StepTone.web,
    _ => null,
  };
}

/// The agent's plan for a turn, as steps. While it works, the first step
/// not done is the one at work when the agent marked none.
List<MainStep> planSteps(TurnSpan turn) {
  final marked = turn.plan.any((e) => e.status == PlanStatus.inProgress);
  final firstTodo = turn.plan.indexWhere((e) => e.status == PlanStatus.pending);
  return [
    for (var i = 0; i < turn.plan.length; i++)
      MainStep(
        label: turn.plan[i].content,
        tone: StepTone.plan,
        state: switch (turn.plan[i].status) {
          PlanStatus.completed => TaskStepState.done,
          // Stopped on the way (limit, error, by the user): not done.
          PlanStatus.inProgress => turn.running
              ? TaskStepState.now
              : (turn.reason == StopReason.endTurn ? TaskStepState.done : TaskStepState.todo),
          PlanStatus.pending => turn.running && !marked && i == firstTodo ? TaskStepState.now : TaskStepState.todo,
        },
      ),
  ];
}

/// « 2 sur 5 »: the plan's step at work, or the last one done.
String planCount(List<MainStep> plan) {
  final done = plan.where((s) => s.state == TaskStepState.done).length;
  final now = plan.any((s) => s.state == TaskStepState.now);
  return '${(done + (now ? 1 : 0)).clamp(1, plan.length)} sur ${plan.length}';
}

MainStep _stepOf(List<ToolItem> group) => MainStep(
  label: stepLabel(group),
  tone: _toneOf(group),
  state: group.any((t) => t.active)
      ? TaskStepState.now
      : (group.any((t) => t.status == ToolStatus.failed) ? TaskStepState.failed : TaskStepState.done),
  note: group.map(toolNote).nonNulls.firstOrNull,
  tools: group,
);

/// Tools in a row grouped in main steps (user request, 2026-09-30: the big
/// lines first, the detail on a click).
List<MainStep> toolSteps(List<ToolItem> tools) => [
  for (final e in turnFlow(tools, const {}))
    if (e is FlowStep) e.step,
];

/// What happened in a turn, in order (user request, 2026-10-05: the
/// actions and the messages in one place).
sealed class FlowEntry {
  const FlowEntry();
}

/// What the agent said on the way, or [thought].
class FlowWords extends FlowEntry {
  const FlowWords(this.text, {this.thought = false});

  final String text;
  final bool thought;
}

/// Tools of one kind in a row: one main step.
class FlowStep extends FlowEntry {
  const FlowStep(this.step);

  final MainStep step;
}

/// A message the user slipped in while the agent worked.
class FlowMe extends FlowEntry {
  const FlowMe(this.item);

  final UserItem item;
}

/// The turn's [items] in order, without the user's opening messages and
/// without [skip] (the answer, shown under the task).
List<FlowEntry> turnFlow(List<ThreadItem> items, Set<ThreadItem> skip) {
  final out = <FlowEntry>[];
  String? group;
  var tools = <ToolItem>[];
  void flush() {
    if (tools.isNotEmpty) out.add(FlowStep(_stepOf(tools)));
    tools = [];
    group = null;
  }

  for (final item in items) {
    if (skip.contains(item)) continue;
    switch (item) {
      case ToolItem():
        final g = _groupOf(item);
        if (g == null) continue;
        if (g != group || g.contains(':')) flush();
        group = g;
        tools.add(item);
      case AgentItem(:final text, :final thought):
        if (text.trim().isEmpty) continue;
        flush();
        out.add(FlowWords(text.trim(), thought: thought));
      case UserItem(:final queued):
        if (!queued) continue;
        flush();
        out.add(FlowMe(item));
    }
  }
  flush();
  return out;
}

/// A finished turn's answer: what the agent said after its last tool.
List<AgentItem> turnAnswer(TurnSpan turn, List<ThreadItem> items) {
  if (turn.running) return const [];
  final out = <AgentItem>[];
  for (final item in items.reversed) {
    if (item is ToolItem) break;
    if (item is AgentItem && !item.thought && item.text.trim().isNotEmpty) out.insert(0, item);
  }
  return out;
}

/// The latest task at a glance, for the notch (user, 2026-10-05: « juste
/// les tâches qui apparaissent et quand c'est fini », no messages): its
/// plan, else its actions; at most [max], around the one at work.
List<MainStep> glanceSteps(SessionLog log, {int max = 4}) {
  // The latest turn with work in it: a question after it has none.
  final turn = log.turns.lastWhere((t) => t.plan.isNotEmpty || turnItems(log, t).any((i) => i is ToolItem), orElse: () => const TurnSpan(-1));
  if (turn.start < 0) return const [];
  final steps = turn.plan.isNotEmpty ? planSteps(turn) : toolSteps(turnItems(log, turn).whereType<ToolItem>().toList());
  if (steps.length <= max) return steps;
  final now = steps.indexWhere((s) => s.state == TaskStepState.now);
  final anchor = now >= 0 ? now : steps.lastIndexWhere((s) => s.state != TaskStepState.todo);
  // Mostly what was done, the step at work, then one to come.
  final start = (anchor - (max - 2)).clamp(0, steps.length - max);
  return steps.sublist(start, start + max);
}

/// The state of a turn's task.
UiStatus taskStatus(TurnSpan turn) => turn.running
    ? UiStatus.working
    : switch (turn.reason) {
        StopReason.cancelled => UiStatus.paused,
        StopReason.rateLimited => UiStatus.limited,
        StopReason.error => UiStatus.error,
        _ => UiStatus.finished,
      };

/// The title of a turn's task: what it does now, or how it ended.
String taskTitle(TurnSpan turn) => turn.running
    ? 'Au travail'
    : switch (turn.reason) {
        StopReason.cancelled => 'Tâche arrêtée',
        StopReason.rateLimited => 'Limite atteinte',
        StopReason.error => 'Tâche en erreur',
        _ => 'Tâche terminée',
      };

/// « 4 étapes · 2 fichiers · 3 min » for a turn's task.
String taskMeta(TurnSpan turn, List<ThreadItem> items, int steps) {
  final files = items.whereType<ToolItem>().where((t) => t.kind == ToolKind.edit && t.status == ToolStatus.completed).map((t) => t.path).toSet().length;
  final start = items.firstOrNull?.at, end = items.lastOrNull?.at;
  final minutes = start == null || end == null ? null : end.difference(start).inMinutes;
  return [
    '$steps étape${steps > 1 ? 's' : ''}',
    if (files > 0) '$files fichier${files > 1 ? 's' : ''}',
    if (!turn.running && minutes != null) minutes < 1 ? 'moins d’une min' : '$minutes min',
  ].join(' · ');
}
