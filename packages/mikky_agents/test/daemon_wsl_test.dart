@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  test('native WSL backend retains permission after the Windows hub exits', () async {
    Future<(Process, DaemonClient)> hub() async {
      final process = await Process.start('../../daemon/target/debug/mikkyd.exe', ['--stdout-endpoint', '--with-wsl']);
      final endpoint = DaemonEndpoint.parse(await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first)!;
      return (process, await DaemonClient.connect(endpoint));
    }

    final (first, client) = await hub();
    final file = File('test/support/fake_agent_linux.py').absolute.path.replaceAll('\\', '/');
    final script = '/mnt/${file[0].toLowerCase()}${file.substring(2)}';
    // Priming the Linux backend through a hub inventory is read-only.
    await client.request('runs.list');
    final run = await DaemonAgentRun.start(
      client,
      provider: AgentProvider.claude,
      host: AgentHost.wsl,
      executable: '/usr/bin/python3',
      args: [script],
      cwd: '/tmp',
    );
    expect(run.runId, startsWith('wsl:'));
    await run.open(cwd: '/tmp');
    final prompt = run.prompt('write');
    if (run.log.pending.isEmpty) {
      await run.changes.firstWhere((_) => run.log.pending.isNotEmpty).timeout(const Duration(seconds: 10));
    }
    await client.close();
    await prompt;
    await first.stdin.close();
    await first.exitCode.timeout(const Duration(seconds: 10));

    final (second, again) = await hub();
    try {
      final runs = await again.request('runs.list') as List;
      expect(runs.any((r) => r['run'] == run.runId && r['alive'] == true), isTrue, reason: 'Expected ${run.runId}; inventory: $runs');
      final restored = await DaemonAgentRun.attach(again, run.runId);
      expect(restored.log.pending, hasLength(1));
      expect(restored.answer(allow: false), isTrue);
      if (restored.log.working) {
        await restored.changes.firstWhere((_) => !restored.log.working).timeout(const Duration(seconds: 10));
      }
      await restored.stop();
      expect(restored.alive, isFalse);
    } finally {
      await again.close();
      await second.stdin.close();
      await second.exitCode.timeout(const Duration(seconds: 10));
    }
  }, skip: Platform.environment['MIKKY_TEST_WSL'] != '1' ? 'Opt in with MIKKY_TEST_WSL=1 after bundling the Linux daemon' : false);
}
