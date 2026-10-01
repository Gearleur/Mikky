import '../support/readers/acp_reader.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

/// Claude's question tool through ACP: the adapter sends a form
/// (`elicitation/create`, as `askUserQuestionsToCreateRequest` builds it in
/// claude-agent-acp 0.84) and waits for the answer.
void main() {
  final at = DateTime.utc(2026, 9, 29, 12);
  Map<String, dynamic> form(Object id) => {
        'jsonrpc': '2.0',
        'id': id,
        'method': 'elicitation/create',
        'params': {
          'mode': 'form',
          'sessionId': 's1',
          'toolCallId': 't1',
          'message': 'Quelle base de données ?',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'question_0': {
                'type': 'string',
                'title': 'Base',
                'oneOf': [
                  {'const': 'SQLite', 'title': 'SQLite', 'description': 'Un fichier, rien à installer'},
                  {'const': 'Postgres', 'title': 'Postgres'},
                ],
              },
              'question_0_custom': {'type': 'string', 'title': 'Other'},
            },
          },
        },
      };

  test('a form is a question with its choices; the agent waits for it', () {
    final reader = AcpReader();
    final log = SessionLog()
      ..applyAll(reader.read({'jsonrpc': '2.0', 'id': 0, 'method': 'session/prompt', 'params': {'sessionId': 's1', 'prompt': []}}, outgoing: true, at: at))
      ..applyAll(reader.read(form(7), outgoing: false, at: at));
    final q = log.question!;
    expect(q.requestId, 7);
    expect(q.questions.single.key, 'question_0');
    expect(q.questions.single.title, 'Base');
    expect(q.questions.single.text, 'Quelle base de données ?');
    expect(q.questions.single.choices.map((c) => c.label), ['SQLite', 'Postgres']);
    expect(q.questions.single.choices.first.description, 'Un fichier, rien à installer');
    expect(q.questions.single.otherKey, 'question_0_custom');
    expect(q.questions.single.multiple, isFalse);
    expect(log.statusAt(at), AgentStatus.question);
    expect(log.detail, 'Quelle base de données ?');

    log.applyAll(reader.read({
      'jsonrpc': '2.0',
      'id': 7,
      'result': {
        'action': 'accept',
        'content': {'question_0': 'SQLite'},
      },
    }, outgoing: true, at: at));
    expect(log.question, isNull);
    expect(log.statusAt(at), isNot(AgentStatus.question));
  });
}
