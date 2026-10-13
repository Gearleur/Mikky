import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

/// What `mikkyd` lists for a question asked by a session it never saw.
Map<String, Object?> _listed({bool normalized = true}) => {
  'id': 3,
  'kind': 'question',
  'sessionId': 'outside',
  'tool': 'AskUserQuestion',
  'title': 'Quelle base ?',
  'cwd': 'C:/projet',
  'agent': 'claude',
  'questions': [
    {
      'question': 'Quelle base ?',
      'header': 'Base',
      'multiSelect': false,
      'options': [
        {'label': 'SQLite', 'description': 'Locale'},
        {'label': 'Postgres', 'description': 'Serveur'},
      ],
    },
  ],
  if (normalized)
    'event': {
      'type': 'question',
      'id': 'hook:3',
      'message': 'Quelle base ?',
      'questions': [
        {
          'key': 'q1',
          'otherKey': 'q1_custom',
          'text': 'Quelle base ?',
          'title': 'Base',
          'multiple': false,
          'choices': [
            {'value': 'SQLite', 'description': 'Locale'},
            {'value': 'Postgres', 'description': 'Serveur'},
          ],
        },
      ],
    },
};

void main() {
  for (final normalized in [true, false]) {
    test('a hook question from an unseen session can be answered (normalized: $normalized)', () async {
      final source = RealAgentSource(clock: () => 0, spawn: (_, _, _) => throw StateError('read only'));
      addTearDown(source.detach);
      source.hookAsks([HookAsk.fromJson(_listed(normalized: normalized))]);
      final entry = source.homeEntries.single;
      expect(entry.status, AgentStatus.question);
      expect(source.questionOf(entry.id)?.questions.single.choices, hasLength(2));
      expect(source.canAnswerQuestion(entry.id), isTrue);
    });
  }

  test('a permission asked in Claude’s app shows but is answered there', () async {
    final source = RealAgentSource(clock: () => 0, spawn: (_, _, _) => throw StateError('read only'));
    addTearDown(source.detach);
    final answered = <(int, String?)>[];
    source.answerHook = (id, decision) => answered.add((id, decision));
    source.hookAsks([
      HookAsk.fromJson({
        'id': 9,
        'sessionId': 'app',
        'tool': 'Bash',
        'title': 'Bash cargo test',
        'command': 'cargo test',
        'answerable': false,
      }),
    ]);
    final entry = source.homeEntries.single;
    expect(entry.status, AgentStatus.approval);
    expect(source.canAnswerRequests(entry.id), isFalse);
    expect(source.canLeaveInTerminal(entry.id), isFalse);
    expect(source.answer(entry.id, AgentAnswer.allow, 0), isFalse);
    // « Plus tard »: off the screens, the app still asks it.
    expect(source.answer(entry.id, AgentAnswer.dismiss, 0), isTrue);
    expect(answered, [(9, null)]);
  });
}
