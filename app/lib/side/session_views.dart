import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/code_card.dart';
import '../ui/feedback.dart';
import '../ui/messages.dart';
import '../ui/metro.dart';
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

/// A message slipped in while the agent worked, for the metro line.
class _Slipped {
  const _Slipped(this.text, this.meta);

  final String text;
  final String? meta;
}

/// The metro line: [slipped] messages go just before the step at work.
List<Widget> _metro(List<SuiviStep> steps, MikkyUi ui, {List<_Slipped> slipped = const []}) {
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

Widget _stepText(SuiviStep s, MikkyUi ui) => s.note != null
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
  final steps = suiviSteps(log, turn);
  final slipped = [
    for (final u in turnItems(log, turn).whereType<UserItem>().where((u) => u.queued)) _Slipped(u.text, u.at == null ? null : clockTime(u.at!)),
  ];
  return [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Expanded(
          child: Text(log.detail.isEmpty ? 'Réfléchit…' : log.detail,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.body, weight: FontWeight.w600, color: ui.text)),
        ),
        const SizedBox(width: 10),
        Text(suiviCount(turn, steps), style: uiText(TextSize.small, color: ui.text2, tabular: true)),
      ]),
    ),
    ..._metro([...steps, if (turn.running) const SuiviStep(StepKind.todo, 'Terminé')], ui, slipped: slipped),
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

/// The star's colors of a main step.
PixelFxPalette? _paletteOf(StepTone? tone, MikkyUi ui) => switch (tone) {
  StepTone.plan || StepTone.created => PixelFxPalette.green(ui),
  StepTone.changed => PixelFxPalette.blue,
  StepTone.deleted => PixelFxPalette.red,
  StepTone.moved => PixelFxPalette.yellow,
  StepTone.ran => PixelFxPalette.fire,
  StepTone.web => PixelFxPalette.violet,
  null => null,
};

/// Chat: the whole conversation. The user's messages in bubbles; each turn
/// with work in it is a task, part of the page, that shows what the agent
/// did — its plan, what it thought and said on the way, every tool — then
/// its answer, the whole width (user request, 2026-09-30). The last task
/// is open, older ones folded.
List<Widget> chatOf(BuildContext context, SessionLog log, {VoidCallback? toSuivi, LimitHooks? limit}) {
  final ui = MikkyUi.of(context);
  final out = <Widget>[];
  void gap([double h = 8]) => out.add(SizedBox(height: h));
  for (final turn in log.turns) {
    final items = turnItems(log, turn);
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
      final steps = [
        for (final s in mainSteps(turn, tools))
          TaskStep(
            label: s.label,
            tone: _paletteOf(s.tone, ui),
            state: s.state,
            note: s.note,
            detail: s.tools.isEmpty
                ? null
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final t in s.tools) _toolLine(t, ui)]),
          ),
      ];
      // Everything, on demand: what it thought and said, every tool.
      final details = <Widget>[
        for (final item in items)
          if (item is ToolItem)
            _toolLine(item, ui)
          else if (item is AgentItem && item.text.trim().isNotEmpty && !identical(item, answer))
            NoteLine(item.text.trim(), thought: item.thought),
      ];
      out.add(TaskSection(
        key: ValueKey('task-${turn.start}'),
        status: taskStatus(turn),
        title: taskTitle(log, turn),
        meta: taskMeta(turn, items, steps.length),
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
      out.add(LimitBlock(log: log, message: turn.message, hooks: limit));
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
