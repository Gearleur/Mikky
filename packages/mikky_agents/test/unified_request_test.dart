import 'dart:async';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'support/hook_requests.dart';

class _Watcher implements SessionWatcher {
  @override
  final sessions = <String, WatchedSession>{};
  final events = StreamController<WatchedSession>.broadcast(sync: true);
  @override
  Stream<WatchedSession> get updates => events.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() => events.close();
  @override
  Future<void> changed(String path) async => events.add(sessions[path]!);
}

void main() {
  test('backend request survives the transcript arriving and is cleared by its snapshot', () async {
    final watcher = _Watcher();
    final source = RealAgentSource(clock: () => 0, spawn: (_, _, _) => throw StateError('read only'));
    addTearDown(() async {
      await source.detach();
      await watcher.stop();
    });
    source.follow(watcher);
    source.hookAsks([permissionAsk(7, 's', 'cargo test')]);
    final entry = source.homeEntries.single;
    expect(entry.log.pending.single.requestId, 'hook:7');
    expect(entry.log.statusAt(DateTime(2026)), entry.status);
    final session = WatchedSession('s.jsonl', AgentProvider.claude, AgentHost.windows);
    session.log.applyAll([const SessionStarted('s'), const TurnStarted(), const UserMessage('Vérifie le moteur')]);
    watcher.sessions[session.path] = session;
    await watcher.changed(session.path);
    expect(source.homeEntries, hasLength(1));
    expect(entry.log, same(session.log));
    expect(entry.log.pending.single.requestId, 'hook:7');
    final version = entry.log.version;
    source.advance(0);
    expect(entry.log.version, version);
    source.hookAsks(const []);
    expect(entry.log.pending, isEmpty);
    expect(entry.status.isBusy, isTrue);
    expect(entry.log.items.whereType<UserItem>(), hasLength(1));
  });
}
