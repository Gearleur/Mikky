import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

List<String> fixtureLines(String name) =>
    File('../mikky_engine/test/fixtures/$name').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();

void main() {
  late Directory home;
  late String claude, codex;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('mikky_watch');
    claude = '${home.path}${Platform.pathSeparator}projects';
    codex = '${home.path}${Platform.pathSeparator}sessions';
    await Directory('$claude/C--p').create(recursive: true);
    await Directory('$codex/2026/09/29').create(recursive: true);
  });
  tearDown(() async => home.delete(recursive: true));

  SessionWatcher watcher() => SessionWatcher(target: WindowsTarget(), claudeProjects: claude, codexSessions: codex, since: const Duration(days: 30000));

  test('reads recent session files at start', () async {
    File('$claude/C--p/1735f552.jsonl').writeAsStringSync('${fixtureLines('claude/wsl_plan.jsonl').join('\n')}\n');
    File('$codex/2026/09/29/rollout-x.jsonl').writeAsStringSync('${fixtureLines('codex/windows_steer.jsonl').join('\n')}\n');
    // Not sessions: a subagent's file, and something else.
    await Directory('$claude/C--p/1735f552/subagents').create(recursive: true);
    File('$claude/C--p/1735f552/subagents/a.jsonl').writeAsStringSync('{}\n');
    File('$codex/2026/09/29/notes.jsonl').writeAsStringSync('{}\n');

    final w = watcher();
    await w.start();
    addTearDown(w.stop);
    final byProvider = {for (final s in w.sessions.values) s.provider: s};
    expect(w.sessions, hasLength(2));
    expect(byProvider[AgentProvider.claude]!.log.title, 'Tâches avec outils de gestion');
    expect(byProvider[AgentProvider.codex]!.log.statusAt(DateTime.now()), AgentStatus.finished);
  });

  test('follows a file as it grows, even cut in the middle of a line', () async {
    final lines = fixtureLines('claude/wsl_plan.jsonl');
    final file = File('$claude/C--p/s.jsonl')..writeAsStringSync('');
    final w = watcher();
    await w.start();
    addTearDown(w.stop);

    final half = lines.length ~/ 2;
    final rest = lines.sublist(half).join('\n');
    file.writeAsStringSync('${lines.sublist(0, half).join('\n')}\n${rest.substring(0, 40)}', mode: FileMode.append);
    await w.changed(file.path);
    final s = w.sessions[file.path]!;
    expect(s.log.working, isTrue);

    file.writeAsStringSync('${rest.substring(40)}\n', mode: FileMode.append);
    await w.changed(file.path);
    expect(s.log.working, isFalse);
    expect(s.log.statusAt(DateTime.now()), AgentStatus.finished);
    expect(s.log.items.whereType<UserItem>(), hasLength(2));
  });

  test('Windows file events reach the watcher', () async {
    final w = watcher();
    await w.start();
    addTearDown(w.stop);
    final got = w.updates.first.timeout(const Duration(seconds: 10));
    File('$codex/2026/09/29/rollout-y.jsonl').writeAsStringSync('${fixtureLines('codex/windows_deny.jsonl').join('\n')}\n');
    final s = await got;
    expect(s.provider, AgentProvider.codex);
    expect(s.host, AgentHost.windows);
  });
}
