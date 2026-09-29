import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 9, 29, 12);
DateTime _at(int s) => _t0.add(Duration(seconds: s));

SessionLog started() => SessionLog()
  ..apply(const SessionStarted('s1'))
  ..apply(TurnStarted(at: _at(0)))
  ..apply(UserMessage('Corrige les tests', at: _at(0)));

void main() {
  test('no turn yet: idle', () {
    expect(SessionLog().statusAt(_t0), AgentStatus.idle);
  });

  test('a turn starts thinking, then works, searches, and finishes', () {
    final log = started();
    expect(log.statusAt(_at(1)), AgentStatus.thinking);

    log.apply(ToolCallEvent('t1', kind: ToolKind.execute, title: 'npm test', status: ToolStatus.running, at: _at(2)));
    expect(log.statusAt(_at(3)), AgentStatus.working);
    expect(log.detail, 'npm test');

    log.apply(ToolCallEvent('t1', status: ToolStatus.completed, at: _at(4)));
    log.apply(ToolCallEvent('t2', kind: ToolKind.search, title: 'grep auth', status: ToolStatus.running, at: _at(5)));
    expect(log.statusAt(_at(6)), AgentStatus.searching);

    log.apply(ToolCallEvent('t2', status: ToolStatus.completed, at: _at(7)));
    log.apply(AgentMessage('Tout passe.\nJ’ai corrigé auth.', messageId: 'm1', at: _at(8)));
    expect(log.statusAt(_at(8)), AgentStatus.thinking);

    log.apply(TurnEnded(StopReason.endTurn, at: _at(9)));
    expect(log.statusAt(_at(10)), AgentStatus.finished);
    expect(log.detail, 'Tout passe.');
    expect(log.turns.single.end, log.items.length);
  });

  test('a permission request waits; AskUserQuestion is a question', () {
    final log = started()
      ..apply(ToolCallEvent('t1', name: 'Bash', kind: ToolKind.execute, title: 'rm -rf cache', status: ToolStatus.pending))
      ..apply(const PermissionAsked(7, toolCallId: 't1', title: 'Bash', command: 'rm -rf cache'));
    expect(log.statusAt(_at(1)), AgentStatus.approval);
    expect(log.detail, 'rm -rf cache');
    log.apply(const PermissionAnswered(7, allowed: true));
    expect(log.statusAt(_at(1)), AgentStatus.working);

    log
      ..apply(const ToolCallEvent('t2', name: 'AskUserQuestion', title: 'Quelle base ?'))
      ..apply(const PermissionAsked(8, toolCallId: 't2', title: 'AskUserQuestion'));
    expect(log.statusAt(_at(2)), AgentStatus.question);
  });

  test('errors and limits keep their message', () {
    final error = started()..apply(const TurnEnded(StopReason.error, message: 'API Error: 500'));
    expect(error.statusAt(_at(1)), AgentStatus.error);
    expect(error.detail, 'API Error: 500');

    final limit = started()..apply(const TurnEnded(StopReason.rateLimited, message: 'Usage limit reached, resets at 5pm'));
    expect(limit.statusAt(_at(1)), AgentStatus.rateLimited);
    expect(limit.detail, contains('resets'));
  });

  test('a new turn closes the one left open', () {
    final log = started()
      ..apply(TurnStarted(at: _at(5)))
      ..apply(UserMessage('Autre chose', at: _at(5)));
    expect(log.turns.first.reason, StopReason.cancelled);
    expect(log.turns, hasLength(2));
    expect(log.working, isTrue);
  });

  test('streamed chunks of one message make one item', () {
    final log = started()
      ..apply(const AgentMessage('Bon', messageId: 'm1'))
      ..apply(const AgentMessage('jour', messageId: 'm1'))
      ..apply(const AgentMessage('Hmm', thought: true));
    expect(log.items.whereType<AgentItem>().map((a) => a.text), ['Bonjour', 'Hmm']);
  });

  test('the version grows at each event', () {
    final log = started();
    final v = log.version;
    log.apply(const TitleChanged('Tests'));
    expect(log.version, v + 1);
    expect(log.title, 'Tests');
  });
}
