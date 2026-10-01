@TestOn('windows')
library;

import 'dart:async';

import '../../mikky_engine/test/support/readers/claude_transcript_reader.dart';
import '../../mikky_engine/test/support/readers/codex_rollout_reader.dart';

import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

Object snapshot(SessionLog log) => [
  log.sessionId,
  log.cwd,
  log.title,
  log.working,
  log.contextUsed,
  log.contextSize,
  [
    for (final p in log.plan) [p.content, p.status.name],
  ],
  [
    for (final t in log.turns) [t.start, t.end, t.reason?.name, t.message],
  ],
  [
    for (final item in log.items)
      switch (item) {
        UserItem() => ['user', item.text, item.queued],
        AgentItem() => ['agent', item.text, item.messageId, item.thought],
        ToolItem() => [
          'tool',
          item.id,
          item.name,
          item.title,
          item.kind.name,
          item.status.name,
          item.command,
          item.path,
          item.output,
          item.diff?.oldText,
          item.diff?.newText,
        ],
      },
  ],
];

void main() {
  late Directory home;
  late Process daemon;
  late DaemonClient client;
  late DaemonSessionWatcher watcher;
  setUp(() async {
    home = await Directory.systemTemp.createTemp('mikky_watch_rust_');
    await Directory('${home.path}/.claude/projects/p').create(recursive: true);
    await Directory('${home.path}/.codex/sessions').create(recursive: true);
    daemon = await Process.start('../../daemon/target/debug/mikkyd.exe', ['--stdout-endpoint', '--watch-home', home.path]);
    final endpoint = DaemonEndpoint.parse(await daemon.stdout.transform(utf8.decoder).transform(const LineSplitter()).first)!;
    client = await DaemonClient.connect(endpoint);
    watcher = DaemonSessionWatcher(client);
    await watcher.start();
  });
  tearDown(() async {
    await watcher.stop();
    await client.close();
    await daemon.stdin.close();
    await daemon.exitCode.timeout(const Duration(seconds: 10));
    await home.delete(recursive: true);
  });

  for (final provider in ['claude', 'codex']) {
    test('Rust $provider reader matches every recorded Dart fixture', () async {
      final fixtures = Directory('../mikky_engine/test/fixtures/$provider')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'));
      var index = 0;
      for (final fixture in fixtures) {
        final file = File(
          provider == 'claude'
              ? '${home.path}/.claude/projects/p/${index++}.jsonl'
              : '${home.path}/.codex/sessions/rollout-${index++}.jsonl',
        );
        final reader = provider == 'claude' ? ClaudeTranscriptReader() : CodexRolloutReader();
        final expected = SessionLog();
        final text = await fixture.readAsString();
        for (final line in const LineSplitter().convert(text).where((s) => s.trim().isNotEmpty)) {
          final value = (jsonDecode(line) as Map).cast<String, dynamic>();
          expected.applyAll(reader is ClaudeTranscriptReader ? reader.read(value) : (reader as CodexRolloutReader).read(value));
        }
        await file.writeAsString('$text\n');
        for (var i = 0; i < 200; i++) {
          if (watcher.sessions.values.any((s) => s.log.version == expected.version && s.log.sessionId == expected.sessionId)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        final actual = watcher.sessions.values.where((s) => s.path == file.path.replaceAll('/', Platform.pathSeparator)).firstOrNull;
        expect(actual, isNotNull, reason: fixture.path);
        expect(snapshot(actual!.log), snapshot(expected), reason: fixture.path);
      }
    });
  }

  test('partial UTF-8 lines wait; appended events are not duplicated; truncation resets', () async {
    final file = File('${home.path}/.claude/projects/p/partial.jsonl');
    const record = '{"type":"user","sessionId":"partial","message":{"content":"été"}}\n';
    final bytes = utf8.encode(record);
    await file.writeAsBytes(bytes.take(bytes.length - 3).toList());
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(watcher.sessions.values.expand((s) => s.log.items), isEmpty);
    final updated = watcher.updates.firstWhere((s) => s.log.items.isNotEmpty);
    await file.writeAsBytes(bytes.skip(bytes.length - 3).toList(), mode: FileMode.append);
    final session = await updated.timeout(const Duration(seconds: 5));
    expect((session.log.items.single as UserItem).text, 'été');
    await watcher.changed(session.path);
    expect(session.log.items, hasLength(1));
    final reset = watcher.updates.firstWhere((s) => s.log.title == 'Fin');
    await file.writeAsString('{"type":"ai-title","aiTitle":"Fin"}\n');
    final replaced = await reset.timeout(const Duration(seconds: 5));
    expect(replaced.log.items, isEmpty);
  });
}
