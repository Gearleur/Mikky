import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/side/session_steps.dart';
import 'package:mikky/ui/metro.dart';
import 'package:mikky/ui/status.dart';
import 'package:mikky/ui/tasks.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// How a session becomes steps (`session_steps.dart`), without a screen.
void main() {
  final t0 = DateTime.utc(2026, 9, 30, 12);

  group('main steps of a task', () {
    const done = TurnSpan(0, end: 6, reason: StopReason.endTurn);

    test('tools of one kind in a row make one step', () {
      final steps = mainSteps(done, const [
        ToolItem('1', kind: ToolKind.read, path: r'C:\app\lib\main.dart', status: ToolStatus.completed),
        ToolItem('2', kind: ToolKind.read, path: '/app/lib/a.dart', status: ToolStatus.completed),
        ToolItem('3', kind: ToolKind.search, status: ToolStatus.completed),
        ToolItem('4', kind: ToolKind.think, status: ToolStatus.completed),
        ToolItem('5', kind: ToolKind.edit, path: '/app/lib/a.dart', diff: FileDiff('/app/lib/a.dart', 'x', 'y'), status: ToolStatus.completed),
        ToolItem('6', kind: ToolKind.edit, path: '/app/lib/b.dart', diff: FileDiff('/app/lib/b.dart', null, 'z'), status: ToolStatus.completed),
      ]);
      expect([for (final s in steps) s.label], ['Explore le code (3)', 'Modifie a.dart', 'Crée b.dart']);
      expect([for (final s in steps) s.tone], [null, StepTone.changed, StepTone.created]);
      expect(steps.first.tools, hasLength(3));
      expect(steps.every((s) => s.state == TaskStepState.done), isTrue);
    });

    test('a refused command is a failed step with its note', () {
      final steps = mainSteps(done, const [
        ToolItem('1', kind: ToolKind.execute, command: 'rm -rf build', status: ToolStatus.failed, output: 'User refused'),
      ]);
      expect(steps.single.label, 'Lance une commande');
      expect(steps.single.state, TaskStepState.failed);
      expect(steps.single.note, 'refusé');
      expect(steps.single.tone, StepTone.ran);
    });

    test('with a plan, the first step not done is the one at work', () {
      const turn = TurnSpan(0, plan: [
        PlanEntry('Lire', PlanStatus.completed),
        PlanEntry('Écrire', PlanStatus.pending),
        PlanEntry('Tester', PlanStatus.pending),
      ]);
      final steps = mainSteps(turn, const []);
      expect([for (final s in steps) s.state], [TaskStepState.done, TaskStepState.now, TaskStepState.todo]);
      expect(steps.every((s) => s.tone == StepTone.plan && s.tools.isEmpty), isTrue);
    });
  });

  group('task head', () {
    test('status and title follow how the turn ended', () {
      final log = SessionLog();
      expect(taskStatus(const TurnSpan(0)), UiStatus.working);
      expect(taskTitle(log, const TurnSpan(0)), 'Au travail');
      expect(taskStatus(const TurnSpan(0, end: 1, reason: StopReason.rateLimited)), UiStatus.limited);
      expect(taskTitle(log, const TurnSpan(0, end: 1, reason: StopReason.cancelled)), 'Tâche arrêtée');
      expect(taskStatus(const TurnSpan(0, end: 1, reason: StopReason.endTurn)), UiStatus.finished);
    });

    test('meta: steps, files changed, minutes', () {
      final items = [
        UserItem('go', at: t0),
        ToolItem('1', kind: ToolKind.edit, path: 'a.dart', status: ToolStatus.completed, at: t0),
        ToolItem('2', kind: ToolKind.edit, path: 'a.dart', status: ToolStatus.completed, at: t0),
        ToolItem('3', kind: ToolKind.edit, path: 'b.dart', status: ToolStatus.completed, at: t0.add(const Duration(minutes: 3))),
      ];
      expect(taskMeta(const TurnSpan(0, end: 4, reason: StopReason.endTurn), items, 2), '2 étapes · 2 fichiers · 3 min');
      expect(taskMeta(const TurnSpan(0), items, 1), '1 étape · 2 fichiers');
    });
  });

  group('Suivi', () {
    test('one step per tool, the one running is at work', () {
      final log = SessionLog()
        ..applyAll([
          TurnStarted(at: t0),
          UserMessage('Corrige le bug', at: t0),
          const ToolCallEvent('1', kind: ToolKind.read, title: 'Read main.dart', status: ToolStatus.completed),
          const ToolCallEvent('2', kind: ToolKind.edit, title: 'Edit main.dart', status: ToolStatus.running, diff: FileDiff('main.dart', 'a', 'b')),
        ]);
      final steps = suiviSteps(log, log.turns.last);
      expect([for (final s in steps) (s.kind, s.text)], [(StepKind.done, 'Read main.dart'), (StepKind.now, 'Edit main.dart')]);
      expect(steps.last.diff?.newText, 'b');
      expect(suiviCount(log.turns.last, steps), '2 étapes');
    });

    test('nothing running yet: it thinks', () {
      final log = SessionLog()..applyAll([TurnStarted(at: t0), UserMessage('Bonjour', at: t0)]);
      expect([for (final s in suiviSteps(log, log.turns.last)) s.text], ['Réfléchit…']);
    });
  });

  test('a change shows two removed lines, then the added ones', () {
    final (:removed, :added) = diffPreview(const FileDiff('a.dart', 'one\n\ntwo\nthree', 'uno\ndos\ntres\ncuatro'));
    expect(removed, ['one', 'two']);
    expect(added, ['uno', 'dos', 'tres']);
    expect(diffCounts(const FileDiff('a.dart', null, 'x\n\ny')), (added: 2, removed: 0));
  });
}
