import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'support/hook_requests.dart';

void main() {
  RealAgentSource source() {
    final s = RealAgentSource(clock: () => 0, spawn: (_, _, _) => throw StateError('read only'));
    addTearDown(s.detach);
    return s;
  }

  test('a hook question from an unseen session can be answered', () {
    final s = source()..hookAsks([questionAsk(3, 'outside', cwd: 'C:/projet')]);
    final entry = s.homeEntries.single;
    expect(entry.status, AgentStatus.question);
    expect(s.questionOf(entry.id)?.questions.first.choices, hasLength(2));
    expect(s.canAnswerQuestion(entry.id), isTrue);
  });

  test('a request answered where the session runs: the agent says so for a while', () {
    var now = DateTime(2026, 10, 13, 15);
    final s = RealAgentSource(clock: () => 0, now: () => now, spawn: (_, _, _) => throw StateError('read only'));
    addTearDown(s.detach);
    s.hookAsks([permissionAsk(5, 'term', 'ls')]);
    final id = s.homeEntries.single.id;
    s
      ..hookAsks(const [])
      ..requestsSettled([
        {'id': 5, 'sessionId': 'term', 'how': 'elsewhere'},
      ]);
    expect(s.agentOf(id)?.detail, 'Répondu dans le terminal');
    // Told once, then gone.
    s.requestsSettled([
      {'id': 5, 'sessionId': 'term', 'how': 'elsewhere'},
    ]);
    now = now.add(const Duration(seconds: 7));
    expect(s.agentOf(id)?.detail, isNot('Répondu dans le terminal'));
    expect(settledNote(timedOut: true, app: AgentApp.vscode), 'Toujours en attente dans VS Code');
  });
}
