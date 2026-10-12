import 'dart:async';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

class _Run implements AgentRun {
  @override
  final log = SessionLog();
  final sent = <String>[];
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  bool get alive => true;
  @override
  String? get sessionId => log.sessionId;
  @override
  String? get workingDirectory => null;
  @override
  Future<void> open({required String cwd, String? resume, String? mode}) async {
    log.apply(const SessionStarted('s'));
  }

  @override
  Future<void> prompt(String text) async {
    sent.add('prompt:$text');
    log.apply(const TurnStarted());
  }

  @override
  Future<void> steer(String text) async => sent.add('steer:$text');
  @override
  Future<void> stop() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('send steers a working agent and prompts an idle one', () async {
    final run = _Run();
    final source = RealAgentSource(clock: () => 0, spawn: (_, _, _) async => run);
    final id = await source.launch(
      const LaunchRequest(provider: AgentProvider.claude, host: AgentHost.windows, cwd: 'p', prompt: 'travaille'),
    );
    await source.send(id, 'suite');
    run.log.apply(const TurnEnded(StopReason.endTurn));
    await source.send(id, 'autre tour');
    expect(run.sent, ['prompt:travaille', 'steer:suite', 'prompt:autre tour']);
    await source.stopAll();
  });
}
