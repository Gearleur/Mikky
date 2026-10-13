import 'dart:async';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_agents/src/daemon/session_wire.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

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
  for (final provider in AgentProvider.values) {
    test('$provider: child before parent, live updates, nested agents, reconnect', () async {
      final now = DateTime(2026, 10, 13, 10);
      final watcher = _Watcher();
      final source = RealAgentSource(clock: () => 1, now: () => now, spawn: (_, _, _) => throw StateError('read only'));
      addTearDown(() async {
        await source.detach();
        await watcher.stop();
      });
      final child = WatchedSession('child', provider, AgentHost.windows)
        ..modified = now
        ..parent = SubAgentLink.fromWire({'session': 'parent', 'agent': 'child', 'tool': 'call_s', 'name': 'Lecteur'});
      child.log.applyAll([const SessionStarted('child'), TurnStarted(at: now)]);
      watcher.sessions['child'] = child;
      source.follow(watcher);
      expect(source.homeEntries, isEmpty);
      final parent = WatchedSession('parent', provider, AgentHost.windows)..modified = now;
      parent.log.applyAll([
        const SessionStarted('parent'),
        TurnStarted(at: now),
        sessionEventFromWire({
          'type': 'tool',
          'id': 'call_s',
          'name': 'agent',
          'title': 'Lecteur',
          'status': 'running',
        })!,
        sessionEventFromWire({'type': 'tool', 'id': 'call_s', 'agent': 'child'})!,
        const TurnEnded(StopReason.endTurn),
      ]);
      watcher.sessions['parent'] = parent;
      await watcher.changed('parent');
      expect(source.entries, hasLength(1));
      expect(
        source.homeEntries.single.log.subAgentOf(parent.log.items.whereType<ToolItem>().single)!.log,
        same(child.log),
      );
      expect(source.agents.single.status.isBusy, isTrue);
      final version = parent.log.version;
      child.log.apply(
        const ToolCallEvent('read', kind: ToolKind.read, title: 'Lit reader.rs', status: ToolStatus.running),
      );
      await watcher.changed('child');
      expect(parent.log.version, greaterThan(version));
      source.advance(1);
      final stable = parent.log.version;
      source.advance(1);
      expect(parent.log.version, stable);
      final nested = WatchedSession('nested', provider, AgentHost.windows)
        ..modified = now
        ..parent = const SubAgentLink(session: 'child', agent: 'nested', name: 'Relecteur');
      nested.log.applyAll([const SessionStarted('nested'), const TurnStarted()]);
      watcher.sessions['nested'] = nested;
      await watcher.changed('nested');
      expect(child.log.subAgents.single.log, same(nested.log));
      child.log.apply(const TurnEnded(StopReason.endTurn));
      nested.log.apply(const TurnEnded(StopReason.endTurn));
      await watcher.changed('child');
      expect(source.entries.single.status, AgentStatus.finished);
      expect(source.homeEntries, hasLength(1));
      source.follow(watcher);
      expect(source.entries, hasLength(1));
      expect(parent.log.subAgents, hasLength(1));
      child.log.apply(TurnStarted(at: now));
      child.log.apply(
        TurnEnded(
          StopReason.rateLimited,
          message: "You've hit your session limit · resets 2:50pm (Europe/Paris)",
          resetsAt: DateTime(2026, 10, 13, 14, 50),
          at: now,
        ),
      );
      await watcher.changed('child');
      expect(source.homeEntries.single.status, AgentStatus.rateLimited);
      expect(source.agents.single.status, AgentStatus.rateLimited);
      expect(parent.log.limitResetsAt, DateTime(2026, 10, 13, 14, 50));
    });
  }
}
