// End-to-end check of the production Rust tool discovery and native WSL path.
// Two tiny real prompts. Does not stop any agent it did not start.
// `--codex-only` tests Codex on Windows and WSL without using Claude.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

Future<void> main(List<String> args) async {
  if (args.any((arg) => arg != '--codex-only')) {
    throw ArgumentError('Usage: dart run tool/backend_smoke.dart [--codex-only]');
  }
  final targets = args.contains('--codex-only')
      ? [
          (AgentProvider.codex, AgentHost.windows, Directory.systemTemp.path),
          (AgentProvider.codex, AgentHost.wsl, '/tmp'),
        ]
      : [
          (AgentProvider.codex, AgentHost.windows, Directory.systemTemp.path),
          (AgentProvider.claude, AgentHost.wsl, '/tmp'),
        ];
  final process = await Process.start('../../daemon/target/debug/mikkyd.exe', ['--stdout-endpoint', '--with-wsl']);
  final endpoint = DaemonEndpoint.parse(await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first)!;
  var client = await DaemonClient.connect(endpoint);
  final runs = <DaemonAgentRun>[];
  try {
    for (final (provider, host, cwd) in targets) {
      final auth = await client.request('tools.auth', {'host': host.name, 'provider': provider.name}) as Map;
      stdout.writeln('${provider.name}/${host.name}: installed=${auth['installed']} connected=${auth['loggedIn']}');
      if (auth['loggedIn'] != true) throw StateError('Sign-in required');
      final run = await DaemonAgentRun.launch(client, provider: provider, host: host, cwd: cwd);
      runs.add(run);
      stdout.writeln('${provider.name}/${host.name}: run=${run.runId}, adapterPid=${run.adapterPid}');
      await run.open(cwd: run.workingDirectory!, mode: modeFor(provider, PermissionMode.ask));
      if (provider == AgentProvider.claude) await run.setModel('sonnet');
      await run
          .prompt('Essai technique de Mikky : réponds uniquement « ok », sans utiliser d’outil ni modifier de fichier.')
          .timeout(const Duration(seconds: 90));
      stdout.writeln('${provider.name}/${host.name}: ${run.log.statusAt(DateTime.now()).name}, answer=${run.log.detail}');
      if (run.log.statusAt(DateTime.now()) != AgentStatus.finished) throw StateError('Agent did not finish normally');
      final sessionId = run.log.sessionId;
      final answer = run.log.detail;
      if (sessionId == null) throw StateError('No session ID after opening the run');
      await client.close();
      client = await DaemonClient.connect(endpoint);
      final inventory = (await client.request('runs.list') as List).cast<Map<String, dynamic>>();
      final listed = inventory.singleWhere((item) => item['run'] == run.runId);
      final again = await DaemonAgentRun.attach(client, run.runId, cwd: cwd, adapterPid: listed['adapterPid'] as int?);
      if (listed['alive'] != true || listed['sessionId'] != sessionId || again.log.detail != answer) {
        throw StateError('Run was not restored after closing its screen');
      }
      if (again.adapterPid != run.adapterPid) throw StateError('Adapter PID changed after reconnect');
      stdout.writeln('${provider.name}/${host.name}: reconnecté, session=$sessionId, adapterPid=${listed['adapterPid']}');
      await again.stop();
      runs.remove(run);
      for (var attempt = 0; attempt < 20; attempt++) {
        final remaining = (await client.request('runs.list') as List).cast<Map<String, dynamic>>();
        if (remaining.every((item) => item['run'] != run.runId)) break;
        if (attempt == 19) throw StateError('Stopped run remains in inventory');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      stdout.writeln('${provider.name}/${host.name}: arrêt confirmé');
    }
  } finally {
    try {
      if (client.isClosed) client = await DaemonClient.connect(endpoint);
      for (final run in runs) {
        try {
          await client.request('run.stop', {'run': run.runId});
        } catch (_) {
          // The daemon may already have removed a run that stopped itself.
        }
      }
    } finally {
      await client.close();
      await process.stdin.close();
      await process.exitCode.timeout(const Duration(seconds: 10));
    }
  }
}
