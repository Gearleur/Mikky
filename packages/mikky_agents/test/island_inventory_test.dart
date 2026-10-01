import 'dart:async';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

/// Sends sessions as updates only, like the Rust backend does with its
/// inventory (at start and after a reconnection).
class _InventoryWatcher implements SessionWatcher {
  final _updates = StreamController<WatchedSession>.broadcast();
  @override
  Map<String, WatchedSession> get sessions => const {};
  @override
  Stream<WatchedSession> get updates => _updates.stream;
  void send(WatchedSession s) => _updates.add(s);
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() => _updates.close();
  @override
  Future<void> changed(String path) async {}
}

void main() {
  late DateTime wall;
  late double clock;
  late RealAgentSource source;
  late _InventoryWatcher watcher;

  setUp(() {
    wall = DateTime(2026, 10, 1, 12);
    clock = 100;
    watcher = _InventoryWatcher();
    source = RealAgentSource(clock: () => clock, now: () => wall, spawn: (p, h, c) async => throw StateError('no'));
    source.follow(watcher);
  });
  tearDown(() => watcher.stop());

  WatchedSession failed(String id, DateTime at) {
    final s = WatchedSession('/$id.jsonl', AgentProvider.claude, AgentHost.windows)..modified = at;
    s.log
      ..apply(SessionStarted(id, cwd: '/p', at: at))
      ..apply(UserMessage('x', at: at))
      ..apply(TurnStarted(at: at))
      ..apply(TurnEnded(StopReason.error, message: 'boom', at: at));
    return s;
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('an old error in the inventory is not news: off the island, like the home', () async {
    watcher.send(failed('old', wall.subtract(const Duration(hours: 40))));
    await flush();
    source.advance(clock);
    final e = source.entries.single;
    expect(e.status, AgentStatus.error);
    expect(e.changedLive, isFalse);
    expect(homeGroupOf(e.homeStatus, e.lastActivity, wall), HomeGroup.history);
    expect(source.agents, isEmpty);
  });

  test('an error seen live leaves the island when it leaves « En attente »', () async {
    final s = failed('new', wall);
    watcher.send(s);
    await flush();
    source.advance(clock);
    final e = source.entries.single;
    expect(e.changedLive, isTrue);
    expect(source.agents.single.status, AgentStatus.error);

    final leaves = source.nextDeadline!;
    expect(leaves, closeTo(clock + homeErrorWaitsFor.inSeconds, .01));
    clock = leaves + 1;
    wall = wall.add(homeErrorWaitsFor + const Duration(seconds: 1));
    expect(source.advance(clock), isTrue);
    expect(source.agents, isEmpty);
    expect(homeGroupOf(e.homeStatus, e.lastActivity, wall), HomeGroup.done);
  });

  test('watched sessions get ids no kept agent can share', () async {
    watcher
      ..send(failed('a', wall))
      ..send(failed('b', wall));
    await flush();
    final ids = source.entries.map((e) => e.id).toList();
    expect(ids.toSet(), hasLength(2));
    expect(ids, everyElement(matches(RegExp(r'^w\d+-\d+$'))));
  });
}
