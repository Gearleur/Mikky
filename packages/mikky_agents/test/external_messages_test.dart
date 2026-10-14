import 'dart:async';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

class _Watcher implements SessionWatcher {
  _Watcher(this.session);
  final WatchedSession session;
  @override
  Map<String, WatchedSession> get sessions => {'external': session};
  @override
  Stream<WatchedSession> get updates => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> changed(String path) async {}
}

void main() {
  for (final provider in AgentProvider.values) {
    test('working external $provider is queued or refused; never starts a second agent', () async {
      var spawned = 0;
      final now = DateTime.now();
      final source = RealAgentSource(
        clock: () => 1,
        spawn: (_, _, _) async {
          spawned++;
          throw StateError('must not spawn');
        },
      );
      final session = WatchedSession('external', provider, AgentHost.windows)..modified = now;
      session.log.applyAll([const SessionStarted('s'), TurnStarted(at: now)]);
      source.follow(_Watcher(session));
      final entry = source.entries.single;
      source.enqueueExternal = (e, id, text) async =>
          ExternalMessage(id: id, sessionId: e.sessionId!, text: text, at: now);
      try {
        await source.send(entry.id, 'Et aussi ceci');
        final message = source.messagesOf(entry.id).single;
        expect(message.text, 'Et aussi ceci');
        expect(message.delivered, isFalse);
        source.externalMessages([
          ExternalMessage(id: message.id, sessionId: 's', text: message.text, at: now, delivered: true),
        ]);
        source.externalMessages([message]);
        expect(
          source.messagesOf(entry.id).single.delivered,
          isTrue,
          reason: 'a late send response cannot undo delivery',
        );
        expect(entry.log.working, isTrue);
        expect(spawned, 0);
      } finally {
        await source.detach();
      }
    });
  }
}
