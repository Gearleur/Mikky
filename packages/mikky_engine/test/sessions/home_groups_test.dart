import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 9, 29, 18);

void main() {
  test('each state goes to its group', () {
    HomeGroup g(AgentStatus s, [Duration ago = const Duration(minutes: 5)]) => homeGroupOf(s, _now.subtract(ago), _now);
    expect(g(AgentStatus.approval), HomeGroup.waiting);
    expect(g(AgentStatus.question), HomeGroup.waiting);
    expect(g(AgentStatus.error), HomeGroup.waiting);
    expect(g(AgentStatus.working), HomeGroup.working);
    expect(g(AgentStatus.thinking), HomeGroup.working);
    expect(g(AgentStatus.searching), HomeGroup.working);
    expect(g(AgentStatus.rateLimited), HomeGroup.working);
    // Paused: unfinished work, with the ones at work, however long ago.
    expect(g(AgentStatus.paused), HomeGroup.working);
    expect(g(AgentStatus.paused, const Duration(days: 2)), HomeGroup.working);
    expect(g(AgentStatus.finished), HomeGroup.done);
    expect(g(AgentStatus.idle), HomeGroup.done);
    const old = Duration(days: 2);
    expect(g(AgentStatus.finished, old), HomeGroup.history);
    expect(g(AgentStatus.error, old), HomeGroup.history);
    // An error left alone for more than 30 min stops waiting.
    expect(g(AgentStatus.error, const Duration(hours: 1)), HomeGroup.done);
    // A request for a yes never goes to the history.
    expect(g(AgentStatus.approval, old), HomeGroup.waiting);
  });

  test('groups are sorted, most recent first, and all present', () {
    final items = [
      ('a', AgentStatus.finished, 30),
      ('b', AgentStatus.working, 2),
      ('c', AgentStatus.finished, 10),
      ('d', AgentStatus.approval, 1),
    ];
    final groups = groupHome(
      items,
      status: (i) => i.$2,
      lastActivity: (i) => _now.subtract(Duration(minutes: i.$3)),
      now: _now,
    );
    expect(groups.keys, HomeGroup.values);
    expect(groups[HomeGroup.waiting]!.map((i) => i.$1), ['d']);
    expect(groups[HomeGroup.working]!.map((i) => i.$1), ['b']);
    expect(groups[HomeGroup.done]!.map((i) => i.$1), ['c', 'a']);
    expect(groups[HomeGroup.history], isEmpty);
  });

  test('real agents keep what they are when their state changes', () {
    const a = Agent(
      id: 'x',
      name: 'Tests',
      status: AgentStatus.working,
      startedAt: 0,
      statusSince: 0,
      provider: AgentProvider.codex,
      host: AgentHost.wsl,
      origin: AgentOrigin.external,
      cwd: '/home/user/projet',
      sessionId: 's1',
      permissions: PermissionMode.ask,
    );
    final b = a.copyWith(status: AgentStatus.finished, name: 'Tests verts');
    expect(b.provider, AgentProvider.codex);
    expect(b.host, AgentHost.wsl);
    expect(b.origin, AgentOrigin.external);
    expect(b.cwd, '/home/user/projet');
    expect(b.sessionId, 's1');
    expect(b.permissions, PermissionMode.ask);
    expect(b.name, 'Tests verts');
  });
}
