import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/cards.dart';
import '../ui/buttons.dart';
import '../ui/feedback.dart';
import '../ui/pixel_fx.dart';
import '../ui/selectors.dart';
import '../ui/surface.dart';
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

/// The icon of what a tool does.
String _toolIcon(ToolKind k) => switch (k) {
  ToolKind.read => 'file',
  ToolKind.edit => 'file',
  ToolKind.delete => 'x',
  ToolKind.move => 'right',
  ToolKind.search || ToolKind.fetch => 'search',
  ToolKind.execute => 'agents',
  ToolKind.think => 'more',
  ToolKind.other => 'sliders',
};

/// One tool the agent used, as a line of its task: what, the command or
/// the file, its state; a tap shows the code it changed or what the
/// command printed.
Widget _toolLine(ToolItem t, MikkyUi ui) {
  final title = t.title.isEmpty ? (t.name ?? 'Outil') : t.title;
  final raw = t.command ?? t.path;
  final detail = raw == null || raw.trim() == title.trim() ? null : raw;
  final diff = t.diff;
  final note = _noteOf(t);
  Widget? trailing;
  if (t.active) {
    trailing = const StatusFx(UiStatus.working, size: 12);
  } else if (note != null) {
    trailing = Text(note, style: uiText(11.5, weight: FontWeight.w500, color: ui.red));
  } else if (diff != null) {
    final added = diff.newText.split('\n').where((l) => l.trim().isNotEmpty).length;
    final removed = (diff.oldText ?? '').split('\n').where((l) => l.trim().isNotEmpty).length;
    trailing = Text.rich(
      TextSpan(children: [
        TextSpan(text: '+$added', style: TextStyle(color: ui.green)),
        if (removed > 0) TextSpan(text: ' −$removed', style: TextStyle(color: ui.red)),
      ]),
      style: uiText(11.5, weight: FontWeight.w500, mono: true),
    );
  }
  final output = t.output?.trim();
  return ToolLine(
    icon: _toolIcon(t.kind),
    title: title,
    detail: detail,
    trailing: trailing,
    body: diff != null ? _code(diff) : (output == null || output.isEmpty ? null : OutputBox(output)),
  );
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
String _stepLabel(List<ToolItem> tools) {
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
      return t.title.isEmpty ? (t.name ?? 'Outil') : t.title;
  }
}

/// The color of an important action (user request, 2026-09-30); reading
/// and searching stay grey.
PixelFxPalette? _stepTone(List<ToolItem> tools, MikkyUi ui) {
  final t = tools.first;
  return switch (t.kind) {
    ToolKind.edit => t.diff != null && t.diff!.oldText == null ? PixelFxPalette.green(ui) : PixelFxPalette.blue,
    ToolKind.delete => PixelFxPalette.red,
    ToolKind.move => PixelFxPalette.yellow,
    ToolKind.execute => PixelFxPalette.fire,
    ToolKind.fetch => PixelFxPalette.violet,
    _ => null,
  };
}

/// The main steps of a turn: its plan when the agent made one, else its
/// tools grouped (user request, 2026-09-30: the big lines first, the
/// detail on a click).
List<Widget> _mainSteps(SessionLog log, TurnSpan turn, List<ToolItem> tools, MikkyUi ui) {
  if (turn.plan.isNotEmpty) {
    // As in Suivi: while it works, the first step not done is the one at
    // work when the agent marked none.
    final marked = turn.plan.any((e) => e.status == PlanStatus.inProgress);
    final firstTodo = turn.plan.indexWhere((e) => e.status == PlanStatus.pending);
    return [
      for (var i = 0; i < turn.plan.length; i++)
        TaskStep(
          label: turn.plan[i].content,
          tone: PixelFxPalette.green(ui),
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
      TaskStep(
        label: _stepLabel(group),
        tone: _stepTone(group, ui),
        state: group.any((t) => t.active)
            ? TaskStepState.now
            : (group.any((t) => t.status == ToolStatus.failed) ? TaskStepState.failed : TaskStepState.done),
        note: group.map(_noteOf).nonNulls.firstOrNull,
        detail: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final t in group) _toolLine(t, ui)]),
      ),
  ];
}

/// Chat: the whole conversation. The user's messages in bubbles; each turn
/// with work in it is a task, part of the page, that shows what the agent
/// did — its plan, what it thought and said on the way, every tool — then
/// its answer, the whole width (user request, 2026-09-30). The last task
/// is open, older ones folded.
List<Widget> chatOf(BuildContext context, SessionLog log, {VoidCallback? toSuivi}) {
  final ui = MikkyUi.of(context);
  final out = <Widget>[];
  void gap([double h = 8]) => out.add(SizedBox(height: h));
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
    final answer = turn.running ? null : items.whereType<AgentItem>().where((a) => !a.thought && a.text.trim().isNotEmpty).lastOrNull;
    if (tools.isNotEmpty || turn.plan.isNotEmpty) {
      final steps = _mainSteps(log, turn, tools, ui);
      // Everything, on demand: what it thought and said, every tool.
      final details = <Widget>[
        for (final item in items)
          if (item is ToolItem)
            _toolLine(item, ui)
          else if (item is AgentItem && item.text.trim().isNotEmpty && !identical(item, answer))
            NoteLine(item.text.trim(), thought: item.thought),
      ];
      final files = tools.where((t) => t.kind == ToolKind.edit && t.status == ToolStatus.completed).map((t) => t.path).toSet().length;
      final start = items.firstOrNull?.at, end = items.lastOrNull?.at;
      final minutes = start == null || end == null ? null : end.difference(start).inMinutes;
      final meta = [
        '${steps.length} étape${steps.length > 1 ? 's' : ''}',
        if (files > 0) '$files fichier${files > 1 ? 's' : ''}',
        if (!turn.running && minutes != null) minutes < 1 ? 'moins d’une min' : '$minutes min',
      ].join(' · ');
      out.add(TaskSection(
        key: ValueKey('task-${turn.start}'),
        status: turn.running
            ? UiStatus.working
            : switch (turn.reason) {
                StopReason.cancelled => UiStatus.sleeping,
                StopReason.rateLimited => UiStatus.limited,
                StopReason.error => UiStatus.error,
                _ => UiStatus.finished,
              },
        title: turn.running
            ? (log.detail.isEmpty ? 'Au travail' : log.detail)
            : switch (turn.reason) {
                StopReason.cancelled => 'Tâche arrêtée',
                StopReason.rateLimited => 'Limite atteinte',
                StopReason.error => 'Tâche en erreur',
                _ => 'Tâche terminée',
              },
        meta: meta,
        initiallyOpen: identical(turn, log.turns.last),
        action: turn.running && toSuivi != null ? 'Suivi' : null,
        onAction: toSuivi,
        steps: steps,
        details: details,
      ));
      gap(6);
    }
    if (turn.running) continue;
    if (turn.reason == StopReason.rateLimited && identical(turn, log.turns.last)) {
      // The subscription's limit: when it lifts, not the raw message (user
      // request, 2026-09-30).
      if (answer != null) {
        out.add(ChatMessage(me: false, text: answer.text.trim()));
        gap(10);
      }
      out.add(LimitCard(resetsAt: log.limitResetsAt, message: turn.message));
      gap(14);
    } else if (answer != null) {
      out.add(ChatMessage(me: false, text: answer.text.trim()));
      gap(14);
    } else if (turn.message != null) {
      out.add(ChatMessage(me: false, text: turn.message!));
      gap(14);
    }
  }
  return out;
}

/// A subscription's limit reached: the yellow state, when it lifts, and
/// what the agent said, small (user request, 2026-09-30).
class LimitCard extends StatelessWidget {
  const LimitCard({super.key, this.resetsAt, this.message});

  final DateTime? resetsAt;
  final String? message;

  @override
  Widget build(BuildContext context) => AgentCard(
        status: UiStatus.limited,
        title: 'Limite de l’abonnement atteinte',
        who: '',
        subtitle: resetsAt == null
            ? (message ?? 'Réessaie plus tard')
            : 'Reprend à ${limitLine(resetsAt).split('reprend à ').last}',
      );
}

/// The permission request at the bottom of the thread: what it asks, the
/// command, Oui / Non.
class AskCard extends StatelessWidget {
  const AskCard({super.key, required this.log, required this.onAnswer});

  final SessionLog log;
  final ValueChanged<AgentAnswer> onAnswer;

  @override
  Widget build(BuildContext context) => AgentCard(
        status: UiStatus.approval,
        title: askLabel(log),
        who: '',
        style: AgentCardStyle.waiting,
        actions: WaitActions(
          command: log.detail,
          onYes: () => onAnswer(AgentAnswer.allow),
          onNo: () => onAnswer(AgentAnswer.deny),
          onAlways: canAlways(log) ? () => onAnswer(AgentAnswer.allowAlways) : null,
        ),
      );
}

/// An agent put on hold: its turn stopped, its session kept. « Reprendre »
/// tells it to go on where it stopped (a message does too).
class PausedCard extends StatelessWidget {
  const PausedCard({super.key, required this.onResume});

  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) => AgentCard(
        status: UiStatus.sleeping,
        title: 'En pause',
        who: '',
        subtitle: 'Travail arrêté, session gardée',
        actions: Align(alignment: Alignment.centerRight, child: AnswerBar(answers: [('Reprendre', onResume)])),
      );
}

/// The agent offers « always allow » for its pending request.
bool canAlways(SessionLog log) => log.pending.firstOrNull?.options.any((o) => o.kind == 'allow_always') ?? false;

/// A question with choices (Claude's question tool): the question, its
/// choices as chips (one, or several), then Envoyer — or Passer, to let
/// the agent go on without an answer.
class QuestionCard extends StatefulWidget {
  const QuestionCard({super.key, required this.question, required this.onAnswer});

  final QuestionAsked question;

  /// The answers by question key; null: skipped.
  final ValueChanged<Map<String, Object>?> onAnswer;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  final Map<String, Set<String>> _picked = {};

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final q = widget.question;
    final complete = q.questions.every((x) => (_picked[x.key] ?? const {}).isNotEmpty);
    return Surface(
      radius: 18,
      color: ui.well,
      shadows: [CssShadow(0, 0, 0, ui.amber.withValues(alpha: .55), spread: 1.5, inset: true)],
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (q.questions.length > 1 || q.questions.first.text.isEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(q.message, style: uiText(14, weight: FontWeight.w600, color: ui.text))),
        for (final x in q.questions) ...[
          if (x.text.isNotEmpty) Text(x.text, style: uiText(q.questions.length > 1 ? 13 : 14, weight: FontWeight.w600, color: ui.text)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in x.choices)
              MChip(
                c.label,
                on: _picked[x.key]?.contains(c.label) ?? false,
                onTap: () => setState(() {
                  final set = _picked[x.key] ??= {};
                  if (x.multiple) {
                    set.contains(c.label) ? set.remove(c.label) : set.add(c.label);
                  } else {
                    set
                      ..clear()
                      ..add(c.label);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 10),
        ],
        Row(children: [
          MButton('Passer', small: true, kind: ButtonKind.ghost, onPressed: () => widget.onAnswer(null)),
          const Spacer(),
          MButton(
            'Envoyer',
            small: true,
            kind: ButtonKind.primary,
            onPressed: complete
                ? () => widget.onAnswer({
                      for (final x in q.questions)
                        x.key: x.multiple ? _picked[x.key]!.toList() : _picked[x.key]!.first,
                    })
                : null,
          ),
        ]),
      ]),
    );
  }
}

/// 950, « 12,3 k », « 1,2 M ».
String formatTokens(int n) {
  String one(double v) => v.toStringAsFixed(v < 10 ? 1 : 0).replaceAll('.', ',').replaceAll(',0', '');
  if (n < 1000) return '$n';
  if (n < 1000000) return '${one(n / 1000)} k';
  return '${one(n / 1000000)} M';
}

/// « Contexte 34 % · 12,3 k jetons » for an agent's page; empty if unknown.
String usageLine(SessionLog log) {
  final parts = <String>[
    if (log.contextSize != null && log.contextUsed != null) 'Contexte ${(100 * log.contextUsed! / log.contextSize!).round()} %',
    if (log.tokens > 0) '${formatTokens(log.tokens)} jetons',
  ];
  return parts.join(' · ');
}

/// « 6 % des 5 h, repart à 18:58 · 10 % de la semaine ».
String limitsLine(LimitsSeen l) {
  String window(LimitWindow w) {
    final span = switch (w.minutes) {
      300 => 'des 5 h',
      10080 => 'de la semaine',
      final m when m % 1440 == 0 => 'des ${m ~/ 1440} j',
      final m when m % 60 == 0 => 'des ${m ~/ 60} h',
      final m => 'des $m min',
    };
    final reset = w.resetsAt;
    final back = reset == null || w.minutes > 1440 ? '' : ', repart à ${clockTime(reset)}';
    return '${w.usedPercent.round()} % $span$back';
  }

  return [if (l.short != null) window(l.short!), if (l.long != null) window(l.long!)].join(' · ');
}
