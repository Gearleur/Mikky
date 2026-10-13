import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  test('approval retains the full command while the island uses a summary', () {
    final command = 'cargo test ${'x' * 160}';
    final log = SessionLog()
      ..setExternalRequest(PermissionAsked('hook:7', toolCallId: null, title: 'Bash', command: command));
    expect(log.detail.length, lessThanOrEqualTo(120));
    expect(log.requestText, command);
    expect(briefOf(log, AgentStatus.approval).request, command);
    log.setExternalRequest(const PermissionAsked('hook:8', toolCallId: null, title: 'Edit app.dart', command: ''));
    expect(log.requestText, 'Edit app.dart');
  });
  test('live snapshots share ACP state without writing duplicate history', () {
    final log = SessionLog()
      ..applyAll([
        const TurnStarted(),
        const UserMessage('Vérifie le moteur'),
        const PermissionAsked(1, toolCallId: null, title: 'ACP', command: 'cargo test'),
      ]);
    final history = log.items.length;
    const permission = PermissionAsked('hook:7', toolCallId: null, title: 'Bash cargo test', command: 'cargo test');
    log.setExternalRequest(permission);
    expect(log.pending.single.requestId, 'hook:7');
    expect(log.statusAt(DateTime(2026)), AgentStatus.approval);
    expect(log.detail, 'cargo test');
    final version = log.version;
    log.setExternalRequest(permission);
    expect(log.version, version);
    const question = QuestionAsked(
      'hook:8',
      message: 'Quelle base ?',
      questions: [Question('q1', text: 'Quelle base ?')],
    );
    log.setExternalRequest(question);
    expect(log.pending, isEmpty);
    expect(log.question, same(question));
    expect(log.statusAt(DateTime(2026)), AgentStatus.question);
    log.apply(const TurnEnded(StopReason.endTurn));
    expect(log.question, same(question));
    expect(log.items, hasLength(history));
    expect(log.turns, hasLength(1));
    log.setExternalRequest(null); // backend timeout or answered in terminal
    expect(log.question, isNull);
    expect(log.statusAt(DateTime(2026)), AgentStatus.finished);
  });
}
