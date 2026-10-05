import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/code_card.dart';
import '../ui/feedback.dart';
import '../ui/messages.dart';
import '../ui/pixel_fx.dart';
import '../ui/status.dart';
import '../ui/tasks.dart';
import '../ui/tokens.dart';
import 'session_cards.dart';
import 'session_steps.dart';
import 'session_text.dart';

/// The code under the step at work: the lines the agent changes.
Widget? _code(FileDiff? diff) {
  if (diff == null) return null;
  final (:removed, :added) = diffPreview(diff);
  var n = 1;
  return CodeCard(file: folderName(diff.path), lines: [
    for (final l in removed) CodeLine(n++, [TextSpan(text: l)], removed: true),
    for (final l in added) CodeLine(n++, [TextSpan(text: l)], added: true),
  ]);
}

/// The agent thinks: its dots, where its words will come.
class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.centerLeft,
        child: Padding(padding: EdgeInsets.symmetric(vertical: 4), child: TypingDots()),
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
  final diff = t.diff;
  final note = toolNote(t);
  Widget? trailing;
  if (t.active) {
    trailing = const StatusFx(UiStatus.working, size: 12);
  } else if (note != null) {
    trailing = Text(note, style: uiText(TextSize.caption, weight: FontWeight.w500, color: ui.red));
  } else if (diff != null) {
    final (:added, :removed) = diffCounts(diff);
    trailing = Text.rich(
      TextSpan(children: [
        TextSpan(text: '+$added', style: TextStyle(color: ui.green)),
        if (removed > 0) TextSpan(text: ' −$removed', style: TextStyle(color: ui.red)),
      ]),
      style: uiText(TextSize.caption, weight: FontWeight.w500, mono: true),
    );
  }
  final output = t.output?.trim();
  return ToolLine(
    icon: _toolIcon(t.kind),
    title: toolTitle(t),
    detail: toolDetail(t),
    trailing: trailing,
    body: diff != null ? _code(diff) : (output == null || output.isEmpty ? null : OutputBox(output)),
  );
}

/// The star's colors of a main step (grey when null: reading, searching).
PixelFxPalette? stepPalette(StepTone? tone, MikkyUi ui) => switch (tone) {
  StepTone.plan || StepTone.created => PixelFxPalette.green(ui),
  StepTone.changed => PixelFxPalette.blue,
  StepTone.deleted => PixelFxPalette.red,
  StepTone.moved => PixelFxPalette.yellow,
  StepTone.ran => PixelFxPalette.fire,
  StepTone.web => PixelFxPalette.violet,
  null => null,
};

/// A main step of a task: its dot and words; a tap shows its tools. The
/// one at work shows the code it writes right under it.
List<Widget> _step(MainStep s, MikkyUi ui) {
  final code = s.state == TaskStepState.now ? _code(s.tools.where((t) => t.active && t.diff != null).lastOrNull?.diff) : null;
  return [
    TaskStep(
      label: s.label,
      tone: stepPalette(s.tone, ui),
      state: s.state,
      note: s.note,
      detail: s.tools.isEmpty ? null : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final t in s.tools) _toolLine(t, ui)]),
    ),
    if (code != null) Padding(padding: const EdgeInsets.fromLTRB(19, 2, 0, 6), child: code),
  ];
}

/// The agent's plan on top of its task: « Plan · 2 sur 5 », its steps.
List<Widget> _plan(TurnSpan turn, MikkyUi ui) {
  final plan = planSteps(turn);
  return [
    Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text('Plan · ${planCount(plan)}', style: uiText(TextSize.small, weight: FontWeight.w500, color: ui.text3, tabular: true)),
    ),
    for (final s in plan) ..._step(s, ui),
  ];
}

/// What happened in a task, in order: the agent's words, its main steps,
/// the messages slipped in; while it works, the dots of what comes.
List<Widget> _flow(TurnSpan turn, List<ThreadItem> items, Set<ThreadItem> answer, MikkyUi ui) {
  final out = <Widget>[];
  Object? previous;
  void add(Object kind, List<Widget> widgets) {
    // A breath between words and steps; steps in a row stay close.
    if (previous != null && (previous != kind || kind != FlowStep)) out.add(const SizedBox(height: 8));
    out.addAll(widgets);
    previous = kind;
  }

  if (turn.plan.isNotEmpty) add(PlanEntry, _plan(turn, ui));
  for (final e in turnFlow(items, answer)) {
    switch (e) {
      case FlowWords(:final text, :final thought):
        add(FlowWords, [NoteLine(text, thought: thought)]);
      case FlowStep(:final step):
        add(FlowStep, _step(step, ui));
      case FlowMe(:final item):
        add(FlowMe, [ChatMessage(me: true, text: item.text, meta: item.at == null ? null : clockTime(item.at!))]);
    }
  }
  if (turn.running && !items.any((i) => i is ToolItem && i.active)) {
    add(_Waiting, [const _Waiting()]);
  }
  return out;
}

/// The thread: the whole conversation, the work in it where it happened
/// (user request, 2026-10-05: one place for the actions and the messages,
/// instead of Suivi and Chat). Your messages in bubbles; each turn with
/// work in it is a task, part of the page, that unfolds what the agent
/// did and said in order; then its answer, the whole width. The last task
/// is open, older ones folded.
List<Widget> threadOf(BuildContext context, SessionLog log, {LimitHooks? limit, ThreadCache? cache}) {
  final ui = MikkyUi.of(context);
  final out = <Widget>[];
  void gap([double h = 8]) => out.add(SizedBox(height: h));
  for (final turn in log.turns) {
    final last = identical(turn, log.turns.last);
    // A finished turn, not the last, never changes: its widgets are kept.
    final kept = !turn.running && !last;
    final widgets = kept ? cache?._of(ui, turn) : null;
    if (widgets != null) {
      out.addAll(widgets);
      continue;
    }
    final from = out.length;
    final items = turnItems(log, turn);
    for (final u in items.whereType<UserItem>().where((u) => !u.queued)) {
      out.add(ChatMessage(me: true, text: u.text, meta: u.at == null ? null : clockTime(u.at!)));
      gap();
    }
    final answer = turnAnswer(turn, items);
    final tools = items.whereType<ToolItem>().toList();
    if (tools.isNotEmpty || turn.plan.isNotEmpty) {
      out.add(TaskSection(
        // Folds once a newer task comes.
        key: ValueKey('task-${turn.start}-$last'),
        status: taskStatus(turn),
        title: taskTitle(turn),
        meta: taskMeta(turn, items, toolSteps(tools).length),
        initiallyOpen: last,
        children: _flow(turn, items, answer.toSet(), ui),
      ));
      gap(6);
    } else if (turn.running) {
      // A plain exchange: the words as they come, then the dots.
      for (final e in turnFlow(items, const {})) {
        if (e case FlowWords(:final text, thought: false)) {
          out.add(ChatMessage(me: false, text: text));
          gap(10);
        } else if (e case FlowMe(:final item)) {
          out.add(ChatMessage(me: true, text: item.text));
          gap();
        }
      }
      out.add(const _Waiting());
    }
    if (turn.running) continue;
    final text = answer.map((a) => a.text.trim()).join('\n\n');
    if (turn.reason == StopReason.rateLimited && last) {
      // The subscription's limit: when it lifts, not the raw message (user
      // request, 2026-09-30).
      if (text.isNotEmpty) {
        out.add(ChatMessage(me: false, text: text));
        gap(10);
      }
      out.add(LimitBlock(log: log, message: turn.message, hooks: limit));
      gap(14);
    } else if (text.isNotEmpty) {
      out.add(ChatMessage(me: false, text: text));
      gap(14);
    } else if (turn.message != null) {
      out.add(ChatMessage(me: false, text: turn.message!));
      gap(14);
    }
    if (kept) cache?._keep(turn, out.sublist(from));
  }
  return out;
}

/// The widgets of a session's finished turns, kept from one build of its
/// page to the next (2026-10-05): the same instances, so Flutter skips
/// them entirely while the last turn goes on.
class ThreadCache {
  MikkyUi? _ui;
  final _turns = <(int, int), List<Widget>>{};

  List<Widget>? _of(MikkyUi ui, TurnSpan turn) {
    // Another theme: everything again.
    if (!identical(ui, _ui)) {
      _turns.clear();
      _ui = ui;
    }
    return _turns[(turn.start, turn.end!)];
  }

  void _keep(TurnSpan turn, List<Widget> widgets) => _turns[(turn.start, turn.end!)] = widgets;
}
