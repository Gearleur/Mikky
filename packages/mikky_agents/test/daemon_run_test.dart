@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'support/fake_agent.dart';

/// The real `mikkyd` (a build of `daemon/`) running the fake agent as a
/// real process: the same scenarios as `agent_run_test.dart`, through it.
/// Build it first: `cargo build` in `daemon/`.
final _mikkyd = File('../../daemon/target/debug/mikkyd.exe');
final _now = DateTime.now();

late Process _daemon;
late DaemonEndpoint _endpoint;

Future<DaemonAgentRun> opened(DaemonClient client, {String? mode, String? resume}) async {
  final run = await DaemonAgentRun.start(
    client,
    provider: AgentProvider.claude,
    host: AgentHost.windows,
    executable: Platform.resolvedExecutable,
    args: [File('test/support/fake_agent_main.dart').absolute.path],
    cwd: Directory.current.path,
  );
  await run.open(cwd: Directory.current.path, mode: mode, resume: resume);
  return run;
}

Future<void> until(AgentRun run, bool Function(SessionLog) test) async {
  if (test(run.log)) return;
  await run.changes.firstWhere((_) => test(run.log)).timeout(const Duration(seconds: 10));
}

void main() {
  setUpAll(() async {
    expect(_mikkyd.existsSync(), isTrue, reason: 'build mikkyd first: cargo build in daemon/');
    _daemon = await Process.start(_mikkyd.path, ['--stdout-endpoint']);
    final line = await _daemon.stdout.transform(utf8.decoder).transform(const LineSplitter()).first;
    _endpoint = DaemonEndpoint.parse(line)!;
  });

  tearDownAll(() async {
    await _daemon.stdin.close();
    await _daemon.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _daemon.kill();
        return -1;
      },
    );
  });

  late DaemonClient client;
  setUp(() async => client = await DaemonClient.connect(_endpoint));
  tearDown(() => client.close());

  test('a wrong token is turned away', () async {
    await expectLater(DaemonClient.connect(DaemonEndpoint(_endpoint.port, 'nope')), throwsA(isA<WebSocketException>()));
  });

  test('two screens receive metadata changes without erasing local pending edits', () async {
    final other = await DaemonClient.connect(_endpoint);
    final first = AgentStore(File('unused-a'))..requireRemote = true;
    final second = AgentStore(File('unused-b'))..requireRemote = true;
    try {
      await first.attach(client);
      await second.attach(other);
      second.setMark('pending', const SessionMark(pinned: true));
      final notice = other.notifications.firstWhere((n) => n.method == 'state.changed');
      first.setMark('shared', const SessionMark(archived: true));
      await first.save();
      await notice.timeout(const Duration(seconds: 5));
      await second.refresh();
      expect(second.mark('shared').archived, isTrue);
      expect(second.mark('pending').pinned, isTrue);
      await second.save();
      await first.refresh();
      expect(first.mark('pending').pinned, isTrue);
      expect(first.mark('shared').archived, isTrue);
    } finally {
      await other.close();
    }
  });

  test('open, prompt: the session fills its log from mikkyd\'s traffic', () async {
    final run = await opened(client, mode: 'default');
    expect(run.sessionId, FakeAgent.sessionId);
    expect(run.log.modes.map((m) => m.id), contains('auto'));
    await run.prompt('bonjour');
    expect(run.log.statusAt(_now), AgentStatus.finished);
    expect(run.log.detail, 'ok');
    await run.stop();
    expect(run.alive, isFalse);
  });

  test('permissions: wait for the yes, « toujours », a no', () async {
    final run = await opened(client);
    var done = run.prompt('write');
    await until(run, (log) => log.pending.isNotEmpty);
    expect(run.log.statusAt(_now), AgentStatus.approval);
    expect(run.answer(allow: true), isTrue);
    await done;
    expect(run.log.items.whereType<ToolItem>().single.status, ToolStatus.completed);
    expect(run.answer(allow: true), isFalse);

    done = run.prompt('write');
    await until(run, (log) => log.pending.isNotEmpty);
    run.answer(allow: false);
    await done;
    expect(run.log.items.whereType<ToolItem>().last.status, ToolStatus.failed);
    await run.stop();
  });

  test('a question: its choices, then the answer goes back', () async {
    final run = await opened(client);
    final done = run.prompt('ask');
    await until(run, (log) => log.question != null);
    expect(run.answerQuestion({'question_0': 'Postgres'}), isTrue);
    await done;
    expect(run.log.question, isNull);
    expect(run.log.detail, 'Choix : Postgres');
    await run.stop();
  });

  test('cancel stops the turn and answers open requests « cancelled »', () async {
    final run = await opened(client);
    final write = run.prompt('write');
    await until(run, (log) => log.pending.isNotEmpty);
    await run.cancel();
    await write;
    expect(run.log.pending, isEmpty);
    expect(run.log.turns.last.reason, StopReason.cancelled);
    await run.stop();
  });

  test('an agent that dies ends its turn in error', () async {
    final run = await opened(client);
    await run.prompt('crash');
    await until(run, (log) => !log.working);
    await until(run, (_) => !run.alive);
    expect(run.log.statusAt(_now), AgentStatus.error);
  });

  test('another screen takes the run back with its whole thread', () async {
    final run = await opened(client);
    await run.prompt('bonjour');
    final other = await DaemonClient.connect(_endpoint);
    final runs = (await other.request('runs.list') as List).cast<Map<String, dynamic>>();
    final listed = runs.singleWhere((r) => r['run'] == run.runId);
    expect(listed['sessionId'], FakeAgent.sessionId);
    expect(run.adapterPid, isA<int>().having((pid) => pid, 'positive PID', greaterThan(0)));
    expect(listed['adapterPid'], run.adapterPid);
    final again = await DaemonAgentRun.attach(other, run.runId, adapterPid: listed['adapterPid'] as int?);
    expect(again.adapterPid, run.adapterPid);
    expect(again.log.turns, hasLength(1));
    expect(again.log.detail, 'ok');
    final done = again.prompt('write');
    // Both screens see the request.
    await until(run, (log) => log.pending.isNotEmpty);
    await until(again, (log) => log.pending.isNotEmpty);
    expect(again.answer(allow: true), isTrue);
    await done;
    await until(run, (log) => !log.working);
    expect(run.log.items.whereType<ToolItem>().single.status, ToolStatus.completed);
    await again.stop();
    await until(run, (_) => !run.alive);
    await other.close();
  });

  test('closing every screen preserves a pending permission; reconnect is incremental', () async {
    final run = await opened(client);
    final prompt = run.prompt('write');
    await until(run, (log) => log.pending.isNotEmpty);
    final before = run.log.items.length;
    final turns = run.log.turns.length;
    await client.close();
    await prompt;
    expect(run.disconnected, isTrue);
    expect(run.log.working, isTrue);
    expect(run.log.pending, isNotEmpty);
    expect(run.answer(allow: true), isFalse);

    await expectLater(run.stop(), throwsA(isA<DaemonError>()));
    expect(run.stopped, isFalse);

    client = await DaemonClient.connect(_endpoint);
    await run.reconnect(client);
    expect(run.log.items.length, before);
    expect(run.log.turns.length, turns);
    expect(run.log.pending, isNotEmpty);
    expect(run.answer(allow: false), isTrue);
    await until(run, (log) => !log.working);
    expect(run.log.items.whereType<ToolItem>().last.status, ToolStatus.failed);
    await run.stop();
  });

  test('questions survive without a screen and an explicit stopAll clears them', () async {
    final run = await opened(client);
    final prompt = run.prompt('ask');
    await until(run, (log) => log.question != null);
    await client.close();
    await prompt;
    client = await DaemonClient.connect(_endpoint);
    final again = await DaemonAgentRun.attach(client, run.runId);
    expect(again.log.question, isNotNull);
    await client.request('runs.stopAll');
    await until(again, (_) => !again.alive);
    expect(again.log.question, isNull);
  });
}
