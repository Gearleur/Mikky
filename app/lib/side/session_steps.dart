import 'package:mikky_engine/mikky_engine.dart';

import '../ui/metro.dart' show StepKind;
import '../ui/status.dart';
import '../ui/tasks.dart' show TaskStepState;
import 'session_text.dart';

// How a session becomes steps, before any widget: the metro line of Suivi,
// the tasks of the chat and their main steps. Pure, testable without a
// screen; `session_views.dart` draws it.

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

// ---------------------------------------------------------------- Suivi

/// A step of the metro line of Suivi.
class SuiviStep {
  const SuiviStep(this.kind, this.text, {this.note, this.diff});

  final StepKind kind;
  final String text;

  /// In red after the text: « refusé », « échec ».
  final String? note;

  /// The change the step at work is writing.
  final FileDiff? diff;
}

/// The steps of a turn: the agent's plan when it made one, else one step
/// per tool it used (the last [maxTools]).
List<SuiviStep> suiviSteps(SessionLog log, TurnSpan turn, {int maxTools = 7}) {
  final tools = turnItems(log, turn).whereType<ToolItem>().toList();
  // Code only while a tool writes it: an old diff under a new step lies.
  final lastDiff = tools.where((t) => t.active && t.diff != null).lastOrNull?.diff;
  if (turn.plan.isNotEmpty) {
    var nowSeen = false;
    final steps = <SuiviStep>[];
    for (final e in turn.plan) {
      switch (e.status) {
        case PlanStatus.completed:
          steps.add(SuiviStep(StepKind.done, e.content));
        case PlanStatus.inProgress:
          nowSeen = true;
          steps.add(SuiviStep(turn.running ? StepKind.now : StepKind.done, e.content, diff: lastDiff));
        case PlanStatus.pending:
          if (turn.running && !nowSeen) {
            nowSeen = true;
            steps.add(SuiviStep(StepKind.now, e.content, diff: lastDiff));
          } else {
            steps.add(SuiviStep(StepKind.todo, e.content));
          }
      }
    }
    return steps;
  }
  final shown = tools.length > maxTools ? tools.sublist(tools.length - maxTools) : tools;
  final steps = <SuiviStep>[
    if (tools.length > maxTools) SuiviStep(StepKind.done, '${tools.length - maxTools} étapes avant'),
    for (final t in shown)
      SuiviStep(
        t.active && turn.running ? StepKind.now : StepKind.done,
        toolTitle(t),
        note: toolNote(t),
        diff: t.active ? t.diff : null,
      ),
  ];
  if (turn.running && !steps.any((s) => s.kind == StepKind.now)) {
    steps.add(const SuiviStep(StepKind.now, 'Réfléchit…'));
  }
  return steps;
}

/// « 2 sur 5 » with a plan, else « 4 étapes ».
String suiviCount(TurnSpan turn, List<SuiviStep> steps) {
  final done = steps.where((s) => s.kind == StepKind.done).length;
  return turn.plan.isNotEmpty ? '${(done + 1).clamp(1, steps.length)} sur ${steps.length}' : '${steps.length} étape${steps.length > 1 ? 's' : ''}';
}

// ----------------------------------------------------------------- Chat

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

/// The main steps of a turn: its plan when the agent made one, else its
/// tools grouped (user request, 2026-09-30: the big lines first, the
/// detail on a click).
List<MainStep> mainSteps(TurnSpan turn, List<ToolItem> tools) {
  if (turn.plan.isNotEmpty) {
    // As in Suivi: while it works, the first step not done is the one at
    // work when the agent marked none.
    final marked = turn.plan.any((e) => e.status == PlanStatus.inProgress);
    final firstTodo = turn.plan.indexWhere((e) => e.status == PlanStatus.pending);
    return [
      for (var i = 0; i < turn.plan.length; i++)
        MainStep(
          label: turn.plan[i].content,
          tone: StepTone.plan,
          state: switch (turn.plan[i].status) {
            PlanStatus.completed => TaskStepState.done,
            PlanStatus.inProgress => turn.running ? TaskStepState.now : TaskStepState.done,
            PlanStatus.pending => turn.running && !marked && i == firstTodo ? TaskStepState.now : TaskStepState.todo,
          },
        ),
    ];
  }
  final groups = <(String, List<ToolItem>)>[];
  for (final t in tools) {
    final g = _groupOf(t);
    if (g == null) continue;
    if (groups.isNotEmpty && groups.last.$1 == g && !g.contains(':')) {
      groups.last.$2.add(t);
    } else {
      groups.add((g, [t]));
    }
  }
  return [
    for (final (_, group) in groups)
      MainStep(
        label: stepLabel(group),
        tone: _toneOf(group),
        state: group.any((t) => t.active)
            ? TaskStepState.now
            : (group.any((t) => t.status == ToolStatus.failed) ? TaskStepState.failed : TaskStepState.done),
        note: group.map(toolNote).nonNulls.firstOrNull,
        tools: group,
      ),
  ];
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
String taskTitle(SessionLog log, TurnSpan turn) => turn.running
    ? (log.detail.isEmpty ? 'Au travail' : log.detail)
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
