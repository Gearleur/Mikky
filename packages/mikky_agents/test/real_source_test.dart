import 'dart:async';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'support/fake_agent.dart';

void main() {
  late double clock;
  late RealAgentSource source;
  late List<FakeAgent> fakes;
  late Directory tmp;
  late AgentStore store;

  setUp(() async {
    clock = 100;
    fakes = [];
    tmp = await Directory.systemTemp.createTemp('mikky_source');
    store = AgentStore(File('${tmp.path}/agents.json'));
    source = RealAgentSource(
      clock: () => clock,
      store: store,
      spawn: (provider, host, cwd) async {
        final f = FakeAgent.inMemory();
        fakes.add(f);
        return AgentRun.connect(f.clientInput, f.clientOutput);
      },
    );
  });
  tearDown(() async {
    await source.stopAll();
    await tmp.delete(recursive: true);
  });

  Future<void> settle(bool Function() test) async {
    for (var i = 0; i < 200 && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(test(), isTrue);
  }

  AgentStatus? statusOf(String id) => source.agents.where((a) => a.id == id).firstOrNull?.status;

  test('launch: the agent works, asks, then finishes and leaves the island', () async {
    final id = await source.launch(const LaunchRequest(provider: AgentProvider.claude, host: AgentHost.wsl, cwd: '/p', prompt: 'write'));
    await settle(() => statusOf(id) == AgentStatus.approval);
    expect(fakes.single.received, ['initialize', 'session/new', 'session/set_mode', 'session/prompt']);
    final agent = source.agents.single;
    expect(agent.detail, 'Write a.txt');
    expect(agent.provider, AgentProvider.claude);
    expect(agent.host, AgentHost.wsl);
    expect(agent.permissions, PermissionMode.ask);

    expect(source.answer(id, AgentAnswer.allow, clock), isTrue);
    await settle(() => statusOf(id) == AgentStatus.finished);
    expect(source.entry(id)!.name, 'Créer a.txt');

    final leaves = source.nextDeadline!;
    expect(leaves, clock + source.finishedLinger);
    clock = leaves + .1;
    expect(source.advance(clock), isTrue);
    expect(source.agents, isEmpty);
    expect(source.entries.single.status, AgentStatus.finished);
  });

  test('launched agents are kept on disk, with their folder and choices', () async {
    final id = await source.launch(const LaunchRequest(provider: AgentProvider.codex, host: AgentHost.windows, cwd: r'C:\p', prompt: 'bonjour', permissions: PermissionMode.auto, model: 'haiku'));
    expect(fakes.single.received, contains('session/set_model'));
    expect(source.entry(id)!.log.modelId, 'haiku');
    await settle(() => store.agents.isNotEmpty && store.agents.single.sessionId != null);
    expect(store.agents.single.permissions, PermissionMode.auto);
    expect(store.recentFolders, [r'C:\p']);
    expect(store.choices[r'C:\p']!.provider, AgentProvider.codex);
    expect(fakes.single.received, contains('session/set_mode'));
  });

  test('a message while it works is slipped in; stop ends it', () async {
    final id = await source.launch(const LaunchRequest(provider: AgentProvider.claude, host: AgentHost.windows, cwd: r'C:\p', prompt: 'slow'));
    await settle(() => statusOf(id) == AgentStatus.working);
    await source.cancel(id);
    await settle(() => source.entry(id)!.status == AgentStatus.idle);
    await source.send(id, 'bonjour');
    await settle(() => source.entry(id)!.status == AgentStatus.finished);
    await source.stop(id);
    expect(source.entry(id)!.live, isFalse);
  });

  test('after a restart: kept agents keep their title; those without a session are forgotten', () async {
    store.agents
      ..add(StoredAgent(id: 'a', provider: AgentProvider.codex, host: AgentHost.wsl, cwd: '/p', permissions: PermissionMode.ask, createdAt: DateTime(2026), sessionId: 's1', title: 'Créer le fichier ok.txt'))
      ..add(StoredAgent(id: 'b', provider: AgentProvider.claude, host: AgentHost.windows, cwd: r'C:\p', permissions: PermissionMode.ask, createdAt: DateTime(2026), title: 'Jamais parti'));
    final again = RealAgentSource(clock: () => clock, store: store, spawn: (p, h, c) async => throw StateError('no'));
    expect(again.entries.map((e) => e.id), ['a']);
    expect(store.agents.map((a) => a.id), ['a']);
    expect(again.entry('a')!.name, 'Créer le fichier ok.txt');
  });

  test('a settled error counts as done, and leaves the island', () async {
    final failing = RealAgentSource(clock: () => clock, store: store, spawn: (p, h, c) async => throw StateError('non'));
    final id = await failing.launch(const LaunchRequest(provider: AgentProvider.claude, host: AgentHost.windows, cwd: r'C:\p', prompt: 'x'));
    final e = failing.entry(id)!;
    expect(e.homeStatus, AgentStatus.error);
    expect(failing.agents, isNotEmpty);
    failing.settle(id);
    expect(e.homeStatus, AgentStatus.finished);
    expect(failing.agents, isEmpty);
  });

  test('an agent that cannot start is in error, with the reason', () async {
    final failing = RealAgentSource(clock: () => clock, spawn: (p, h, c) async => throw const ProcessException('node', [], 'introuvable'));
    final id = await failing.launch(const LaunchRequest(provider: AgentProvider.claude, host: AgentHost.windows, cwd: r'C:\p', prompt: 'x'));
    expect(failing.entry(id)!.status, AgentStatus.error);
    expect(failing.agents.single.detail, contains('introuvable'));
    expect(failing.answer(id, AgentAnswer.dismiss, clock), isTrue);
    expect(failing.agents, isEmpty);
  });

  group('sessions started elsewhere', () {
    late Directory home;
    late SessionWatcher watcher;
    setUp(() async {
      home = await Directory.systemTemp.createTemp('mikky_follow');
      await Directory('${home.path}/projects/C--p').create(recursive: true);
      await Directory('${home.path}/sessions').create(recursive: true);
      watcher = SessionWatcher(
        target: WindowsTarget(),
        claudeProjects: '${home.path}${Platform.pathSeparator}projects',
        codexSessions: '${home.path}${Platform.pathSeparator}sessions',
        since: const Duration(days: 30000),
      );
    });
    tearDown(() async {
      await watcher.stop();
      await home.delete(recursive: true);
    });

    test('show in the home as external; a finished one read at start stays off the island', () async {
      final lines = File('../mikky_engine/test/fixtures/claude/wsl_plan.jsonl').readAsLinesSync();
      File('${home.path}/projects/C--p/a.jsonl').writeAsStringSync('${lines.join('\n')}\n');
      await watcher.start();
      source.follow(watcher);
      final e = source.entries.single;
      expect(e.origin, AgentOrigin.external);
      expect(e.provider, AgentProvider.claude);
      expect(e.name, 'Tâches avec outils de gestion');
      expect(e.status, AgentStatus.finished);
      expect(source.agents, isEmpty);
      expect(e.live, isFalse);
    });

    test('a resumed session (« fork ») stands for its original, whose error no longer waits', () async {
      final lines = File('../mikky_engine/test/fixtures/claude/wsl_plan.jsonl').readAsLinesSync();
      File('${home.path}/projects/C--p/orig.jsonl').writeAsStringSync('${lines.join('\n')}\n');
      // The fork: the same history (same message ids) under a new session.
      final fork = lines.map((l) => l.replaceAll('1735f552-326a-4423-82d2-138c1e35ba31', 'f0f0f0f0-0000-0000-0000-000000000000'));
      File('${home.path}/projects/C--p/fork.jsonl').writeAsStringSync('${fork.join('\n')}\n{"type":"ai-title","aiTitle":"La suite","sessionId":"f0f0f0f0-0000-0000-0000-000000000000"}\n');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      File('${home.path}/projects/C--p/fork.jsonl').setLastModifiedSync(DateTime.now());
      await watcher.start();
      source.follow(watcher);
      expect(source.entries, hasLength(2));
      expect(source.homeEntries.map((e) => e.name), ['La suite']);
    });

    test('marks: rename, pin, archive, settle, forget (and the file with it)', () async {
      final lines = File('../mikky_engine/test/fixtures/claude/wsl_plan.jsonl').readAsLinesSync();
      final file = File('${home.path}/projects/C--p/a.jsonl')..writeAsStringSync('${lines.join('\n')}\n');
      await watcher.start();
      source.follow(watcher);
      final e = source.entries.single;
      source.rename(e.id, 'Mon essai');
      expect(e.name, 'Mon essai');
      source.setPinned(e.id, true);
      source.setArchived(e.id, true);
      expect((e.mark.pinned, e.mark.archived), (true, true));
      source.rename(e.id, '');
      expect(e.name, 'Tâches avec outils de gestion');
      await source.forget(e.id, deleteFile: true);
      expect(file.existsSync(), isFalse);
      expect(source.homeEntries, isEmpty);
      await store.saved;
      final again = AgentStore(store.file);
      await again.load();
      expect(again.marks.values.single.forgotten, isTrue);
    });

    test('a session Mikky launched is shown once', () async {
      final id = await source.launch(const LaunchRequest(provider: AgentProvider.claude, host: AgentHost.windows, cwd: r'C:\p', prompt: 'bonjour'));
      await settle(() => source.entry(id)!.sessionId != null);
      final file = File('${home.path}/projects/C--p/${FakeAgent.sessionId}.jsonl')
        ..writeAsStringSync('{"type":"ai-title","aiTitle":"Autre","sessionId":"${FakeAgent.sessionId}"}\n');
      await watcher.start();
      source.follow(watcher);
      await watcher.changed(file.path);
      expect(source.entries, hasLength(1));
      expect(source.entries.single.id, id);
    });
  });
}
