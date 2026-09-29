import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

final _now = DateTime.utc(2026, 9, 29, 13);

List<UserItem> users(SessionLog log) => log.items.whereType<UserItem>().toList();
List<ToolItem> tools(SessionLog log) => log.items.whereType<ToolItem>().toList();
ToolItem tool(SessionLog log, String title) => tools(log).firstWhere((t) => t.title.contains(title));

void main() {
  group('Claude through ACP', () {
    test('a refusal and a slipped message, in one turn', () {
      final log = replayAcp('claude_windows_steer_deny.jsonl');
      expect(log.title, 'Gestion des tâches avec TaskCreate et TaskUpdate');
      expect(log.turns, hasLength(1));
      expect(log.turns.single.reason, StopReason.endTurn);
      expect(log.statusAt(_now), AgentStatus.finished);
      expect(users(log).map((u) => u.queued), [false, true]);
      expect(users(log).last.text, contains('c.txt'));
      expect(tool(log, 'Write b.txt').status, ToolStatus.failed);
      expect(tool(log, 'Write a.txt').diff!.newText, 'un');
      expect(log.plan.map((e) => e.content), contains('Créer c.txt contenant « trois »'));
    });

    test('the slipped message waits after the answer being written', () {
      final log = replayAcp('claude_windows_steer_deny.jsonl');
      final i = log.items.indexWhere((t) => t is UserItem && t.queued);
      final before = log.items[i - 1] as AgentItem;
      expect(before.text, endsWith('au fur et à mesure.'));
    });

    test('waits for a yes on a permission request, then works again', () {
      final asked = replayAcp('claude_wsl_plan.jsonl', until: (log, _) => log.pending.isNotEmpty);
      expect(asked.statusAt(_now), AgentStatus.approval);
      expect(asked.detail, 'Write a.txt');
      expect(asked.pending.single.options.map((o) => o.kind), containsAll(['allow_once', 'reject_once']));

      var seen = false;
      final answered = replayAcp('claude_wsl_plan.jsonl', until: (log, _) {
        seen |= log.pending.isNotEmpty;
        return seen && log.pending.isEmpty;
      });
      expect(answered.statusAt(_now), isNot(AgentStatus.approval));
      expect(answered.working, isTrue);
    });

    test('the plan moves step by step: the metro line', () {
      final plans = <List<PlanEntry>>[];
      replayAcp('claude_wsl_plan.jsonl', until: (log, _) {
        if (plans.isEmpty || plans.last != log.plan) plans.add(log.plan);
        return false;
      });
      expect(plans.any((p) => p.any((e) => e.status == PlanStatus.inProgress)), isTrue);
      final last = plans.last;
      expect(last, hasLength(4));
      expect(last.every((e) => e.status == PlanStatus.completed), isTrue);
    });

    test('cancel ends the turn and stops its tools; the fallback mode wins', () {
      final log = replayAcp('claude_windows_cancel.jsonl');
      expect(log.turns.last.reason, StopReason.cancelled);
      expect(log.statusAt(_now), AgentStatus.idle);
      expect(log.detail, '');
      expect(tool(log, 'ping').status, ToolStatus.failed);
      // Auto was asked, but Haiku falls back to Accept edits.
      expect(log.modeId, 'acceptEdits');
    });

    test('Claude lists its models as a config option', () {
      final log = replayAcp('claude_wsl_plan.jsonl');
      expect(log.modelOption, 'model');
      expect(log.models.map((m) => m.id), containsAll(['default', 'opus', 'sonnet']));
      expect(log.models.firstWhere((m) => m.id == 'opus').name, 'Opus 5.5');
    });

    test('a loaded session replays its thread, and is done', () {
      final log = replayAcp('claude_windows_list_load.jsonl');
      expect(log.sessionId, '5f6e39b6-4370-47a2-bfac-95a2c859bb8a');
      expect(users(log).first.text, startsWith('Essai technique'));
      expect(log.turns.every((t) => !t.running), isTrue);
      expect(log.statusAt(_now), AgentStatus.finished);
      expect(tool(log, 'Write b.txt').status, ToolStatus.failed);
    });
  });

  group('Codex through ACP', () {
    test('a no stops the whole turn', () {
      final asked = replayAcp('codex_windows_deny.jsonl', until: (log, _) => log.pending.isNotEmpty);
      expect(asked.modeId, 'read-only');
      expect(asked.models, isNotEmpty);
      expect(asked.statusAt(_now), AgentStatus.approval);
      expect(asked.detail, contains('d.txt'));

      final log = replayAcp('codex_windows_deny.jsonl');
      expect(log.turns.single.reason, StopReason.cancelled);
      expect(log.statusAt(_now), AgentStatus.idle);
      expect(tool(log, 'e.txt').status, ToolStatus.failed);
    });

    test('only the slipped prompt is answered: the turn still ends', () {
      final log = replayAcp('codex_windows_steer.jsonl');
      expect(log.turns, hasLength(1));
      expect(log.turns.single.reason, StopReason.endTurn);
      expect(log.statusAt(_now), AgentStatus.finished);
      expect(users(log).map((u) => u.queued), [false, true]);
    });

    test('in WSL, the request shows the clean command, not the shell around it', () {
      final asked = replayAcp('codex_wsl_permissions.jsonl', until: (log, _) => log.pending.isNotEmpty);
      expect(asked.pending.single.command, contains('/usr/bin/zsh'));
      expect(asked.detail, "printf 'un' > a.txt");

      final log = replayAcp('codex_wsl_permissions.jsonl');
      expect(log.turns, hasLength(2));
      expect(log.detail, 'fini');
    });
  });
}
