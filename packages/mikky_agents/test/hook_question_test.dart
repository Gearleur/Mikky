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

  test('a question asked in Claude’s app shows but is answered there', () {
    final s = source()..hookAsks([questionAsk(4, 'app', answerable: false)]);
    final entry = s.homeEntries.single;
    expect(entry.status, AgentStatus.question);
    expect(s.canAnswerQuestion(entry.id), isFalse);
  });

  test('a permission asked in Claude’s app shows but is answered there', () {
    final answered = <(int, String?)>[];
    final s = source()
      ..answerHook = ((id, decision) => answered.add((id, decision)))
      ..hookAsks([permissionAsk(9, 'app', 'cargo test', answerable: false)]);
    final entry = s.homeEntries.single;
    expect(entry.status, AgentStatus.approval);
    expect(s.canAnswerRequests(entry.id), isFalse);
    expect(s.canLeaveInTerminal(entry.id), isFalse);
    expect(s.answer(entry.id, AgentAnswer.allow, 0), isFalse);
    // « Plus tard »: off the screens, the app still asks it.
    expect(s.answer(entry.id, AgentAnswer.dismiss, 0), isTrue);
    expect(answered, [(9, null)]);
  });
}
