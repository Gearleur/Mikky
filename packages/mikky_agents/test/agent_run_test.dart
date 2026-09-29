import 'dart:async';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'support/fake_agent.dart';

final _now = DateTime.now();

Future<(FakeAgent, AgentRun)> opened({bool autoFallback = false, String? mode, String? resume}) async {
  final agent = FakeAgent.inMemory(autoFallback: autoFallback);
  final run = AgentRun.connect(agent.clientInput, agent.clientOutput);
  await run.open(cwd: '/tmp/x', mode: mode, resume: resume);
  return (agent, run);
}

/// Waits until [test] holds on [run]'s log.
Future<void> until(AgentRun run, bool Function(SessionLog) test) async {
  if (test(run.log)) return;
  await run.changes.firstWhere((_) => test(run.log)).timeout(const Duration(seconds: 5));
}

void main() {
  test('modes for each permission choice (A0 probe)', () {
    expect(modeFor(AgentProvider.claude, PermissionMode.ask), 'default');
    expect(modeFor(AgentProvider.claude, PermissionMode.auto), 'auto');
    expect(modeFor(AgentProvider.codex, PermissionMode.ask), 'read-only');
    expect(modeFor(AgentProvider.codex, PermissionMode.auto), 'agent');
  });

  test('Mikky offers every model but Haiku', () {
    final models = offeredModels(const [SessionModel('opus', 'Opus 5.5'), SessionModel('haiku', 'Haiku 4.5'), SessionModel('claude-haiku-4-5', 'Fast')]);
    expect(models.map((m) => m.id), ['opus']);
  });

  test('open, prompt, answer: the session fills its log', () async {
    final (agent, run) = await opened(mode: 'default');
    expect(agent.received, ['initialize', 'session/new', 'session/set_mode']);
    expect(run.sessionId, FakeAgent.sessionId);
    expect(run.log.modes.map((m) => m.id), contains('auto'));
    expect(run.log.models.map((m) => m.id), ['opus', 'haiku']);
    await run.prompt('bonjour');
    expect(run.log.statusAt(_now), AgentStatus.finished);
    expect(run.log.detail, 'ok');
  });

  test('a permission request waits for the yes, then the tool runs', () async {
    final (_, run) = await opened();
    final done = run.prompt('write');
    await until(run, (log) => log.pending.isNotEmpty);
    expect(run.log.statusAt(_now), AgentStatus.approval);
    expect(run.log.detail, 'Write a.txt');
    expect(run.answer(allow: true), isTrue);
    await done;
    final tool = run.log.items.whereType<ToolItem>().single;
    expect(tool.status, ToolStatus.completed);
    expect(run.log.plan.single.status, PlanStatus.completed);
    expect(run.log.title, 'Créer a.txt');
    expect(run.log.statusAt(_now), AgentStatus.finished);
    expect(run.answer(allow: true), isFalse);
  });

  test('a no refuses the tool', () async {
    final (_, run) = await opened();
    final done = run.prompt('write');
    await until(run, (log) => log.pending.isNotEmpty);
    run.answer(allow: false);
    await done;
    expect(run.log.items.whereType<ToolItem>().single.status, ToolStatus.failed);
  });

  test('cancel stops the turn, and answers open requests « cancelled »', () async {
    final (_, run) = await opened();
    final slow = run.prompt('slow');
    await until(run, (log) => log.items.whereType<ToolItem>().isNotEmpty);
    expect(run.log.statusAt(_now), AgentStatus.working);
    await run.cancel();
    await slow;
    expect(run.log.turns.last.reason, StopReason.cancelled);
    expect(run.log.statusAt(_now), AgentStatus.idle);
    expect(run.log.items.whereType<ToolItem>().single.status, ToolStatus.failed);

    final write = run.prompt('write');
    await until(run, (log) => log.pending.isNotEmpty);
    await run.cancel();
    await write;
    expect(run.log.pending, isEmpty);
    expect(run.log.turns.last.reason, StopReason.cancelled);
  });

  test('an agent that dies ends its turn in error', () async {
    final (_, run) = await opened();
    await run.prompt('crash');
    await until(run, (log) => !log.working);
    expect(run.alive, isFalse);
    expect(run.log.statusAt(_now), AgentStatus.error);
    expect(run.log.detail, "L'agent s'est arrêté");
  });

  test('a usage limit shows as limited', () async {
    final (_, run) = await opened();
    await run.prompt('limit');
    expect(run.log.statusAt(_now), AgentStatus.rateLimited);
    expect(run.log.detail, contains('resets'));
  });

  test('the mode the agent really took wins', () async {
    final (_, run) = await opened(autoFallback: true, mode: 'auto');
    expect(run.log.modeId, 'acceptEdits');
  });

  test('resuming replays the thread, then goes on', () async {
    final (agent, run) = await opened(resume: FakeAgent.sessionId);
    expect(agent.received, contains('session/load'));
    expect(run.log.items.whereType<UserItem>().single.text, 'Avant');
    expect(run.log.statusAt(_now), AgentStatus.finished);
    await run.prompt('encore');
    expect(run.log.turns, hasLength(2));
  });

  test('a real process: spawn, talk, stop', () async {
    final run = await AgentRun.spawn(WindowsTarget(), Platform.resolvedExecutable, ['test/support/fake_agent_main.dart']);
    await run.open(cwd: Directory.current.path);
    await run.prompt('bonjour');
    expect(run.log.statusAt(_now), AgentStatus.finished);
    await run.stop();
    expect(run.alive, isFalse);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
