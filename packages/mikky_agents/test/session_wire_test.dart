import 'package:mikky_agents/src/daemon/session_wire.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

/// Folds events as mikkyd sends them.
SessionLog fold(List<Map<String, dynamic>> events) => SessionLog()..applyAll(events.map(sessionEventFromWire).nonNulls);

void main() {
  final now = DateTime(2026, 10, 12, 18);

  test('a Codex exec script is a live tool: running, still going, done', () {
    final log = fold([
      {'type': 'start'},
      {
        'type': 'tool',
        'id': 'call_1',
        'name': 'exec_command',
        'kind': 'search',
        'title': "rg --files -g '*home*'",
        'status': 'running',
        'command': "rg --files -g '*home*'",
        'path': null,
      },
    ]);
    expect(log.statusAt(now), AgentStatus.searching);
    expect(log.detail, "rg --files -g '*home*'");
    // What it printed so far, still running (no status).
    log.apply(sessionEventFromWire({'type': 'tool', 'id': 'call_1', 'output': 'app/lib/home/home_view.dart'})!);
    final tool = log.items.whereType<ToolItem>().single;
    expect(tool.active, isTrue);
    expect(tool.output, 'app/lib/home/home_view.dart');
    log.apply(sessionEventFromWire({'type': 'tool', 'id': 'call_1', 'status': 'failed', 'output': null})!);
    expect(log.items.whereType<ToolItem>().single.status, ToolStatus.failed);
    expect(log.items.whereType<ToolItem>().single.title, "rg --files -g '*home*'");
  });

  test('a Codex file change in two parts: both, with their lines, counted together', () {
    Map<String, dynamic> part(int line, String old, String now) => {
      'path': r'C:\p\a.dart',
      'old': old,
      'new': now,
      'line': line,
    };
    final parts = [part(10, 'a\n', 'a\nb\n'), part(40, 'x\ny\n', 'z\n')];
    final log = fold([
      {'type': 'start'},
      {
        'type': 'tool',
        'id': 'call_7',
        'name': 'apply_patch',
        'kind': 'edit',
        'title': 'Edit a.dart',
        'status': 'completed',
        'path': r'C:\p\a.dart',
        'diff': parts.first,
        'diffs': parts,
      },
    ]);
    final tool = log.items.whereType<ToolItem>().single;
    expect(tool.changes.map((d) => d.line), [10, 40]);
    expect(activityOf(log).single.diff, const DiffStat(2, 2));
    // A later update without a diff keeps them.
    log.apply(sessionEventFromWire({'type': 'tool', 'id': 'call_7', 'output': 'ok'})!);
    expect(log.items.whereType<ToolItem>().single.changes, hasLength(2));
  });

  test('a Codex question waits for the user, then work goes on', () {
    final log = fold([
      {'type': 'start'},
      {
        'type': 'question',
        'id': 'call_q',
        'message': 'Quel verre ?',
        'questions': [
          {
            'key': 'q1',
            'text': 'Quel verre ?',
            'title': null,
            'multiple': false,
            'otherKey': null,
            'choices': [
              {'value': 'Verre blanc', 'description': ''},
              {'value': 'Verre noir', 'description': ''},
            ],
          },
        ],
      },
    ]);
    expect(log.statusAt(now), AgentStatus.question);
    expect(log.detail, 'Quel verre ?');
    log
      ..apply(sessionEventFromWire({'type': 'questionAnswered', 'id': 'call_q'})!)
      ..apply(sessionEventFromWire({'type': 'user', 'text': 'Verre blanc', 'queued': true})!);
    expect(log.question, isNull);
    expect(log.statusAt(now), AgentStatus.thinking);
  });

  test('Codex Desktop messages each make their own item', () {
    final log = fold([
      {'type': 'start'},
      {'type': 'user', 'text': 'rends les tuiles plus plates', 'queued': false},
      {'type': 'message', 'text': 'Je regarde les planches.', 'id': 'said-1'},
      {'type': 'message', 'text': "C'est fait.", 'id': 'said-2'},
      {'type': 'end', 'reason': 'endTurn'},
    ]);
    expect(log.items.whereType<AgentItem>().map((a) => a.text), ['Je regarde les planches.', "C'est fait."]);
    expect(log.statusAt(now), AgentStatus.finished);
  });
}
