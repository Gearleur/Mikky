import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/cards.dart';
import '../ui/feedback.dart';
import '../ui/thread.dart';
import '../ui/tokens.dart';

/// « à l'instant », « il y a 4 min », « hier »…
String ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'à l’instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24 && t.day == now.day) return 'il y a ${d.inHours} h';
  final yesterday = now.subtract(const Duration(days: 1));
  if (t.year == yesterday.year && t.month == yesterday.month && t.day == yesterday.day) return 'hier';
  return 'le ${t.day}/${t.month}';
}

String clockTime(DateTime t) {
  final l = t.toLocal();
  return '${l.hour}:${l.minute.toString().padLeft(2, '0')}';
}

/// « Claude », « Codex · WSL ».
String whoOf(AgentEntry e) => '${e.provider == AgentProvider.claude ? 'Claude' : 'Codex'}${e.host == AgentHost.wsl ? ' · WSL' : ''}';

String folderName(String? path) =>
    path == null ? '' : path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ?? path;

/// What a permission request asks, in words.
String askLabel(SessionLog log) {
  final asked = log.pending.firstOrNull;
  if (asked == null) return 'Attend ton feu vert';
  final tool = log.items.whereType<ToolItem>().where((t) => t.id == asked.toolCallId).firstOrNull;
  return switch (tool?.kind) {
    ToolKind.execute => 'Veut lancer une commande',
    ToolKind.edit => 'Veut modifier un fichier',
    ToolKind.delete => 'Veut supprimer un fichier',
    ToolKind.move => 'Veut déplacer un fichier',
    ToolKind.fetch => 'Veut aller sur internet',
    _ => 'Attend ton feu vert',
  };
}

List<ThreadItem> _itemsOf(SessionLog log, TurnSpan turn) => log.items.sublist(turn.start, turn.end ?? log.items.length);

/// A step of the metro line, before it becomes a widget.
class _Step {
  const _Step(this.kind, this.text, {this.note, this.diff});

  final StepKind kind;
  final String text;

  /// In red after the text: « refusé », « échec ».
  final String? note;
  final FileDiff? diff;
}

String? _noteOf(ToolItem t) {
  if (t.status != ToolStatus.failed) return null;
  final out = (t.output ?? '').toLowerCase();
  return out.contains('refused') || out.contains('rejected') || out.contains('denied') ? 'refusé' : 'échec';
}

/// The steps of a turn: the agent's plan when it made one, else one step
/// per tool it used (the last [maxTools]).
List<_Step> _steps(SessionLog log, TurnSpan turn, {int maxTools = 7}) {
  final items = _itemsOf(log, turn);
  final tools = items.whereType<ToolItem>().toList();
  // Code only while a tool writes it: an old diff under a new step lies.
  final lastDiff = tools.where((t) => t.active && t.diff != null).lastOrNull?.diff;
  if (turn.plan.isNotEmpty) {
    var nowSeen = false;
    final steps = <_Step>[];
    for (final e in turn.plan) {
      switch (e.status) {
        case PlanStatus.completed:
          steps.add(_Step(StepKind.done, e.content));
        case PlanStatus.inProgress:
          nowSeen = true;
          steps.add(_Step(turn.running ? StepKind.now : StepKind.done, e.content, diff: lastDiff));
        case PlanStatus.pending:
          if (turn.running && !nowSeen) {
            nowSeen = true;
            steps.add(_Step(StepKind.now, e.content, diff: lastDiff));
          } else {
            steps.add(_Step(StepKind.todo, e.content));
          }
      }
    }
    return steps;
  }
  final shown = tools.length > maxTools ? tools.sublist(tools.length - maxTools) : tools;
  final steps = <_Step>[
    if (tools.length > maxTools) _Step(StepKind.done, '${tools.length - maxTools} étapes avant'),
    for (final t in shown)
      _Step(
        t.active && turn.running ? StepKind.now : StepKind.done,
        t.title.isEmpty ? (t.name ?? 'Outil') : t.title,
        note: _noteOf(t),
        diff: t.active ? t.diff : null,
      ),
  ];
  if (turn.running && !steps.any((s) => s.kind == StepKind.now)) {
    steps.add(const _Step(StepKind.now, 'Réfléchit…'));
  }
  return steps;
}

/// The code under the step at work: the lines the agent changes.
Widget? _code(FileDiff? diff) {
  if (diff == null) return null;
  final removed = (diff.oldText ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(2).toList();
  final added = diff.newText.split('\n').take(removed.isEmpty ? 5 : 3).toList();
  var n = 1;
  return CodeCard(file: folderName(diff.path), lines: [
    for (final l in removed) CodeLine(n++, [TextSpan(text: l)], removed: true),
    for (final l in added) CodeLine(n++, [TextSpan(text: l)], added: true),
  ]);
}

/// A message slipped in while the agent worked, for the metro line.
class _Slipped {
  const _Slipped(this.text, this.meta);

  final String text;
  final String? meta;
}

/// The metro line: [slipped] messages go just before the step at work.
List<Widget> _metro(List<_Step> steps, MikkyUi ui, {List<_Slipped> slipped = const []}) {
  final rows = <(StepKind, Widget, String?)>[];
  final nowAt = steps.indexWhere((s) => s.kind == StepKind.now);
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
    if (i == nowAt) {
      for (final m in slipped) {
        rows.add((StepKind.me, Text(m.text), m.meta));
      }
    }
    final code = s.kind == StepKind.now ? _code(s.diff) : null;
    final text = _stepText(s, ui);
    rows.add((
      s.kind,
      code == null ? text : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, const SizedBox(height: 8), code]),
      null,
    ));
  }
  final past = nowAt < 0 ? rows.length : rows.indexWhere((r) => r.$1 == StepKind.now);
  return [
    for (var i = 0; i < rows.length; i++)
      MetroStep(kind: rows[i].$1, past: i < past, first: i == 0, last: i == rows.length - 1, meta: rows[i].$3, child: rows[i].$2),
  ];
}

Widget _stepText(_Step s, MikkyUi ui) => s.note != null
    ? Text.rich(
        TextSpan(children: [TextSpan(text: s.text), TextSpan(text: ' · ${s.note}', style: TextStyle(color: ui.red, fontWeight: FontWeight.w500))]),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      )
    : Text(s.text, maxLines: 2, overflow: TextOverflow.ellipsis);

/// Suivi: what the agent does now, then the metro line of its turn, with
/// the messages slipped in while it works just before the step at work.
List<Widget> suiviOf(BuildContext context, SessionLog log) {
  final ui = MikkyUi.of(context);
  final turn = log.turns.lastOrNull;
  if (turn == null) return [const _Waiting()];
  final steps = _steps(log, turn);
  final done = steps.where((s) => s.kind == StepKind.done).length;
  final count = turn.plan.isNotEmpty ? '${(done + 1).clamp(1, steps.length)} sur ${steps.length}' : '${steps.length} étape${steps.length > 1 ? 's' : ''}';
  final slipped = [
    for (final u in _itemsOf(log, turn).whereType<UserItem>().where((u) => u.queued)) _Slipped(u.text, u.at == null ? null : clockTime(u.at!)),
  ];
  return [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Expanded(
          child: Text(log.detail.isEmpty ? 'Réfléchit…' : log.detail,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(14.5, weight: FontWeight.w600, color: ui.text)),
        ),
        const SizedBox(width: 10),
        Text(count, style: uiText(12, color: ui.text2, tabular: true)),
      ]),
    ),
    ..._metro([...steps, if (turn.running) const _Step(StepKind.todo, 'Terminé')], ui, slipped: slipped),
  ];
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: TypingDots()),
      );
}

/// Chat: the whole conversation. Each turn with work in it is a task card:
/// live (back to Suivi) while it runs, « Tâche terminée » after.
List<Widget> chatOf(BuildContext context, SessionLog log, {VoidCallback? toSuivi}) {
  final ui = MikkyUi.of(context);
  final out = <Widget>[];
  void gap() => out.add(const SizedBox(height: 8));
  for (final turn in log.turns) {
    final items = _itemsOf(log, turn);
    final users = items.whereType<UserItem>().toList();
    final tools = items.whereType<ToolItem>().toList();
    for (final u in users.where((u) => !u.queued)) {
      out.add(ChatMessage(me: true, text: u.text, meta: u.at == null ? null : clockTime(u.at!)));
      gap();
    }
    for (final u in users.where((u) => u.queued)) {
      out.add(ChatMessage(me: true, text: u.text));
      gap();
    }
    if (tools.isNotEmpty || turn.plan.isNotEmpty) {
      if (turn.running) {
        out.add(TaskCard(title: log.detail.isEmpty ? 'Au travail' : log.detail, subtitle: 'Voir le suivi', live: true, onTap: toSuivi));
        gap();
        continue;
      }
      final files = tools.where((t) => t.kind == ToolKind.edit && t.status == ToolStatus.completed).map((t) => t.path).toSet().length;
      final start = items.firstOrNull?.at, end = items.lastOrNull?.at;
      final minutes = start == null || end == null ? null : end.difference(start).inMinutes;
      final title = switch (turn.reason) {
        StopReason.cancelled => 'Tâche arrêtée',
        StopReason.error || StopReason.rateLimited => 'Tâche en erreur',
        _ => 'Tâche terminée',
      };
      final steps = _steps(log, turn);
      out.add(TaskCard(
        title: title,
        subtitle: [
          '${steps.length} étape${steps.length > 1 ? 's' : ''}',
          if (files > 0) '$files fichier${files > 1 ? 's' : ''}',
          if (minutes != null) minutes < 1 ? 'moins d’une min' : '$minutes min',
        ].join(' · '),
        steps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _metro(steps, ui)),
      ));
      gap();
    }
    if (turn.running) continue;
    final answer = items.whereType<AgentItem>().where((a) => !a.thought && a.text.trim().isNotEmpty).lastOrNull;
    if (answer != null) {
      out.add(ChatMessage(me: false, text: answer.text.trim()));
      gap();
    } else if (turn.message != null) {
      out.add(ChatMessage(me: false, text: turn.message!));
      gap();
    }
  }
  return out;
}

/// The permission request at the bottom of the thread: what it asks, the
/// command, Oui / Non.
class AskCard extends StatelessWidget {
  const AskCard({super.key, required this.log, required this.onAnswer});

  final SessionLog log;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) => AgentCard(
        status: UiStatus.approval,
        title: askLabel(log),
        who: '',
        style: AgentCardStyle.waiting,
        actions: WaitActions(command: log.detail, onYes: () => onAnswer(true), onNo: () => onAnswer(false)),
      );
}
