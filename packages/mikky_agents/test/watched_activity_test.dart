import 'dart:async';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'support/hook_requests.dart';

class _Watcher implements SessionWatcher {
  final events = StreamController<WatchedSession>.broadcast(sync: true);
  @override
  final sessions = <String, WatchedSession>{};
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
  late DateTime now;
  late RealAgentSource source;
  late _Watcher watcher;
  late WatchedSession session;
  setUp(() {
    now = DateTime.utc(2026, 10, 16, 12);
    source = RealAgentSource(clock: () => 100, now: () => now, spawn: (_, _, _) => throw StateError('observer only'));
    watcher = _Watcher();
    source.follow(watcher);
    session = WatchedSession('observed', AgentProvider.codex, AgentHost.windows);
    watcher.sessions[session.path] = session;
    session.log.apply(SessionStarted('observed', at: now));
  });
  tearDown(() async {
    await source.detach();
    await watcher.stop();
  });

  test('inventory is silent, then real progress and completion are announced once', () async {
    session.replaying = true;
    session.log.apply(TurnStarted(at: now));
    await watcher.changed(session.path);
    expect(source.agents.single.announceChanges, isFalse);
    session.replaying = false;
    now = now.add(const Duration(seconds: 1));
    session.log.apply(AgentMessage('nouvelle activité', at: now));
    await watcher.changed(session.path);
    expect(source.agents.single.announceChanges, isTrue);
    session.log.apply(TurnEnded(StopReason.endTurn, at: now));
    await watcher.changed(session.path);
    final entry = source.entries.single;
    source.answer(entry.id, AgentAnswer.dismiss, 100);
    session.log.apply(TitleChanged('métadonnée seulement', at: now.add(const Duration(seconds: 1))));
    await watcher.changed(session.path);
    expect(source.agents, isEmpty, reason: 'a title must not revive a dismissed completion');
    expect(entry.announceChanges, isFalse);
  });

  test('usage updates cannot revive an abandoned turn or reset its activity time', () async {
    session.log.apply(TurnStarted(at: now));
    await watcher.changed(session.path);
    final activityAt = source.entries.single.lastActivity;
    now = now.add(const Duration(minutes: 20));
    session.log.apply(LimitsSeen(at: now));
    await watcher.changed(session.path);
    expect(source.entries.single.status, AgentStatus.idle);
    expect(source.entries.single.lastActivity, activityAt);
    expect(source.agents, isEmpty);
    session.log.apply(TurnStarted(at: now));
    await watcher.changed(session.path);
    expect(source.agents.single.status, AgentStatus.thinking);
    expect(source.agents.single.announceChanges, isTrue);
  });

  test('hook inventory is silent and duplicate hook snapshots do not revive an ignored request', () {
    final ask = permissionAsk(1, 'hook-session', 'commande');
    source.hookAsks([ask], replay: true);
    expect(source.agents.single.announceChanges, isFalse);
    source.entries.single.dismissed = true;
    source.hookAsks([ask]);
    expect(source.agents, isEmpty);
    source.hookAsks([permissionAsk(2, 'hook-session', 'autre commande')]);
    expect(source.agents.single.announceChanges, isTrue);
  });

  test('an abandoned child has a deadline and its expiry cannot announce a false completion', () async {
    session.log.applyAll([TurnStarted(at: now), TurnEnded(StopReason.endTurn, at: now)]);
    await watcher.changed(session.path);
    final child = WatchedSession('child', AgentProvider.codex, AgentHost.windows)
      ..parent = const SubAgentLink(session: 'observed', agent: 'child');
    child.log.applyAll([SessionStarted('child', at: now), TurnStarted(at: now)]);
    watcher.sessions[child.path] = child;
    await watcher.changed(child.path);
    expect(source.agents.single.status.isBusy, isTrue);
    expect(source.nextDeadline, 100 + const Duration(minutes: 15).inSeconds);
    now = now.add(const Duration(minutes: 15));
    source.advance(100);
    expect(source.entries.single.status, AgentStatus.finished);
    expect(source.entries.single.announceChanges, isFalse);
  });
}
