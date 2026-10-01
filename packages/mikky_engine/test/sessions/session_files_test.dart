import '../support/readers/codex_rollout_reader.dart';
import '../support/readers/claude_transcript_reader.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('Claude session file', () {
    test('title, plan, slipped message and refusal', () {
      final log = replayClaude('wsl_plan.jsonl');
      expect(log.sessionId, '1735f552-326a-4423-82d2-138c1e35ba31');
      expect(log.cwd, '/tmp/essai-wsl');
      expect(log.title, 'Tâches avec outils de gestion');
      expect(log.statusAt(log.lastEventAt!), AgentStatus.finished);
      expect(log.plan.map((e) => e.content), ['Créer a.txt avec « un »', 'Créer b.txt avec « deux »', 'Supprimer hello.txt', 'Créer c.txt avec « trois »']);
      expect(log.items.whereType<UserItem>().map((u) => u.queued), [false, true]);
      final write = log.items.whereType<ToolItem>().firstWhere((t) => t.title == 'Write b.txt');
      expect(write.status, ToolStatus.failed);
      expect(write.diff!.newText, 'deux');
    });

    test('a file cut in the middle of a command is at work, until it goes stale', () {
      final reader = ClaudeTranscriptReader();
      final log = SessionLog();
      for (final line in fixture('claude/wsl_plan.jsonl')) {
        log.applyAll(reader.read(line));
        if (log.items.whereType<ToolItem>().any((t) => (t.command ?? '').startsWith('rm ') && t.active)) break;
      }
      final last = log.lastEventAt!;
      expect(log.statusAt(last), AgentStatus.working);
      // Claude's own words for the command, not the command.
      expect(log.detail, 'Supprimer hello.txt avec rm');
      const stale = Duration(minutes: 15);
      expect(log.statusAt(last.add(const Duration(minutes: 5)), staleAfter: stale), AgentStatus.working);
      expect(log.statusAt(last.add(const Duration(hours: 1)), staleAfter: stale), AgentStatus.idle);
    });

    test('an interruption by the user ends the turn', () {
      final reader = ClaudeTranscriptReader();
      final log = SessionLog();
      for (final line in fixture('claude/wsl_plan.jsonl').take(8)) {
        log.applyAll(reader.read(line));
      }
      log.applyAll(reader.read({
        'type': 'user',
        'timestamp': '2026-09-29T13:30:00.000Z',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '[Request interrupted by user]'},
          ],
        },
      }));
      expect(log.turns.last.reason, StopReason.cancelled);
      expect(log.statusAt(DateTime.utc(2026, 9, 29, 14)), AgentStatus.idle);
    });
  });

  group('Codex session file', () {
    test('a slipped message, then done', () {
      final log = replayCodex('windows_steer.jsonl');
      expect(log.sessionId, '01a0ed3d-5250-7a31-adca-693bec6dcd0f');
      expect(log.title, isNull);
      expect(log.items.whereType<UserItem>().first.text, startsWith('Essai technique'));
      expect(log.turns.single.reason, StopReason.endTurn);
      expect(log.statusAt(log.lastEventAt!), AgentStatus.finished);
      expect(log.items.whereType<UserItem>().map((u) => u.queued), [false, true]);
      expect(log.items.whereType<ToolItem>().map((t) => t.title), contains('Remove-Item a.txt'));
    });

    test('a refused command aborts the turn', () {
      final log = replayCodex('windows_deny.jsonl');
      expect(log.turns.single.reason, StopReason.cancelled);
      expect(log.statusAt(log.lastEventAt!), AgentStatus.idle);
    });

    test('between task_started and task_complete, the agent is at work', () {
      final reader = CodexRolloutReader();
      final log = SessionLog();
      for (final line in fixture('codex/windows_steer.jsonl')) {
        log.applyAll(reader.read(line));
        if (log.items.whereType<ToolItem>().length == 2) break;
      }
      expect(log.working, isTrue);
      expect(log.statusAt(log.lastEventAt!).isBusy, isTrue);
    });
  });
}
