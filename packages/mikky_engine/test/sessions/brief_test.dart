import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 10, 4, 12);
DateTime _at(int s) => _t0.add(Duration(seconds: s));

SessionLog started(String prompt) => SessionLog()
  ..apply(const SessionStarted('s1'))
  ..apply(TurnStarted(at: _at(0)))
  ..apply(UserMessage(prompt, at: _at(0)));

void main() {
  group('diffStat', () {
    test('a new file: every line added', () {
      expect(diffStat(const FileDiff('a.dart', null, 'a\nb\nc\n')), const DiffStat(3, 0));
    });

    test('one line changed in the middle', () {
      expect(diffStat(const FileDiff('a', 'a\nb\nc\nd', 'a\nB\nc\nd')), const DiffStat(1, 1));
    });

    test('lines added and removed, in order', () {
      expect(diffStat(const FileDiff('a', 'x\ny\nz', 'x\nnew\ny')), const DiffStat(1, 1));
      expect(diffStat(const FileDiff('a', 'a\nb', 'a\nb\nc\nd')), const DiffStat(2, 0));
      expect(diffStat(const FileDiff('a', 'a\nb\nc', '')), const DiffStat(0, 3));
    });

    test('too big: counted in any order', () {
      final old = List.generate(3000, (i) => 'l$i').join('\n');
      final now = List.generate(3000, (i) => i == 10 ? 'changed' : 'l$i').join('\n');
      final d = diffStat(FileDiff('big', old, now));
      expect(d, const DiffStat(1, 1));
      expect(d.tooLarge, isTrue);
    });
  });

  test('activity: the latest tools of the turn, with their diff', () {
    final log = started('Ajoute un test')
      ..apply(ToolCallEvent('t1', kind: ToolKind.read, title: 'Read main.dart', status: ToolStatus.completed, at: _at(1)))
      ..apply(ToolCallEvent(
        't2',
        kind: ToolKind.edit,
        title: 'Edit main.dart',
        path: '/p/lib/main.dart',
        diff: const FileDiff('/p/lib/main.dart', 'a\nb', 'a\nB\nc'),
        status: ToolStatus.completed,
        at: _at(2),
      ))
      ..apply(ToolCallEvent('t3', kind: ToolKind.execute, title: 'Run', command: 'dart test', status: ToolStatus.running, at: _at(3)));
    final lines = activityOf(log);
    expect(lines.map((l) => l.text), ['Read main.dart', 'Modifie main.dart', 'dart test']);
    expect(lines[1].diff, const DiffStat(2, 1));
    expect(lines.last.running, isTrue);
    expect(activityOf(log, max: 1).single.text, 'dart test');
  });

  test('an approval brings the task, the step, the last words and the command', () {
    final log = started('Corrige le build\net lance les tests')
      ..apply(const PlanChanged([
        PlanEntry('Lire le code', PlanStatus.completed),
        PlanEntry('Lancer les tests', PlanStatus.inProgress),
        PlanEntry('Corriger', PlanStatus.pending),
      ]))
      ..apply(AgentMessage('J’ai lu le code.\n\nJe lance la suite de tests.', messageId: 'm1', at: _at(1)))
      ..apply(ToolCallEvent('t1', name: 'Bash', kind: ToolKind.execute, title: 'cargo test', command: 'cargo test', status: ToolStatus.pending, at: _at(2)))
      ..apply(const PermissionAsked(7, toolCallId: 't1', title: 'Bash', command: 'cargo test'));
    final b = briefOf(log, log.statusAt(_at(3)));
    expect(b.kind, BriefKind.approval);
    expect(b.task, 'Corrige le build et lance les tests');
    expect(b.step, '2/3 · Lancer les tests');
    expect(b.said, 'Je lance la suite de tests.');
    expect(b.request, 'cargo test');
    expect(b.recent.single.text, 'cargo test');
  });

  test('a file change waiting for a yes says how big', () {
    final log = started('Renomme')
      ..apply(const ToolCallEvent(
        't1',
        name: 'Edit',
        kind: ToolKind.edit,
        title: 'Edit lib/a.dart',
        path: 'lib/a.dart',
        diff: FileDiff('lib/a.dart', 'x\ny', 'x\nz\nw'),
        status: ToolStatus.pending,
      ))
      ..apply(const PermissionAsked(1, toolCallId: 't1', title: 'Edit lib/a.dart'));
    final b = briefOf(log, AgentStatus.approval);
    expect(b.request, 'Modifier a.dart');
    expect(b.requestTitle, 'lib/a.dart');
    expect(b.requestDiff, const DiffStat(2, 1));
  });

  test('finished: the summary and the files changed', () {
    final log = started('Fais-le')
      ..apply(const ToolCallEvent('t1', kind: ToolKind.edit, diff: FileDiff('a.dart', null, '1\n2'), status: ToolStatus.completed))
      ..apply(const ToolCallEvent('t2', kind: ToolKind.edit, diff: FileDiff('a.dart', '1\n2', '1\n3'), status: ToolStatus.completed))
      ..apply(const ToolCallEvent('t3', kind: ToolKind.edit, diff: FileDiff('b.dart', null, 'x'), status: ToolStatus.failed))
      ..apply(AgentMessage('## Fait\n\n**Tout** passe.', at: _at(4)))
      ..apply(TurnEnded(StopReason.endTurn, at: _at(5)));
    final b = briefOf(log, AgentStatus.finished);
    expect(b.request, 'Fait');
    expect(b.said, isNull);
    expect(b.files.map((f) => '${f.name} ${f.diff}'), ['a.dart +3 −1']);
  });

  test('an error brings its message', () {
    final log = started('Va')..apply(const TurnEnded(StopReason.error, message: 'API Error: 500'));
    final b = briefOf(log, AgentStatus.error);
    expect(b.request, 'API Error: 500');
    expect(b.task, 'Va');
  });
}
