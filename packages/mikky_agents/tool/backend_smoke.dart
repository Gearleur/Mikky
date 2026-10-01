// End-to-end check of the production Rust tool discovery and native WSL path.
// Two tiny real prompts. Does not stop any agent it did not start.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

Future<void> main() async {
  final process = await Process.start('../../daemon/target/debug/mikkyd.exe', ['--stdout-endpoint', '--with-wsl']);
  final endpoint = DaemonEndpoint.parse(await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first)!;
  final client = await DaemonClient.connect(endpoint);
  final runs = <DaemonAgentRun>[];
  try {
    for (final (provider, host, cwd) in [
      (AgentProvider.codex, AgentHost.windows, Directory.systemTemp.path),
      (AgentProvider.claude, AgentHost.wsl, '/tmp'),
    ]) {
      final auth = await client.request('tools.auth', {'host': host.name, 'provider': provider.name}) as Map;
      stdout.writeln('${provider.name}/${host.name}: installed=${auth['installed']} connected=${auth['loggedIn']}');
      if (auth['loggedIn'] != true) throw StateError('Sign-in required');
      final run = await DaemonAgentRun.launch(client, provider: provider, host: host, cwd: cwd);
      runs.add(run);
      await run.open(cwd: run.workingDirectory!, mode: modeFor(provider, PermissionMode.ask));
      if (provider == AgentProvider.claude) await run.setModel('sonnet');
      await run
          .prompt('Essai technique de Mikky : réponds uniquement « ok », sans utiliser d’outil ni modifier de fichier.')
          .timeout(const Duration(seconds: 90));
      stdout.writeln('${provider.name}/${host.name}: ${run.log.statusAt(DateTime.now()).name}, answer=${run.log.detail}');
      if (run.log.statusAt(DateTime.now()) != AgentStatus.finished) throw StateError('Agent did not finish normally');
    }
  } finally {
    for (final run in runs) {
      await run.stop();
    }
    await client.close();
    await process.stdin.close();
    await process.exitCode.timeout(const Duration(seconds: 10));
  }
}
