// A real Codex permission request through mikkyd, with no approved write.
// The screen is closed while the request waits; another screen refuses it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

Future<void> main(List<String> args) async {
  if (args.any((arg) => arg != '--wsl')) throw ArgumentError('Usage: dart run tool/codex_permission_smoke.dart [--wsl]');
  final wsl = args.contains('--wsl');
  final scratch = wsl ? null : await Directory.systemTemp.createTemp('mikky-codex-permission-');
  final cwd = scratch?.path ?? '/tmp';
  final markerName = wsl ? 'mikky-codex-permission-${DateTime.now().microsecondsSinceEpoch}.txt' : 'probe.txt';
  final markerPath = wsl ? '/tmp/$markerName' : '${scratch!.path}${Platform.pathSeparator}$markerName';
  Future<bool> markerExists() async => wsl
      ? (await Process.run('wsl.exe', ['-d', 'Ubuntu', '--', 'test', '-e', markerPath])).exitCode == 0
      : File(markerPath).existsSync();
  final process = await Process.start('../../daemon/target/debug/mikkyd.exe', ['--stdout-endpoint', if (wsl) '--with-wsl']);
  final endpoint = DaemonEndpoint.parse(await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first)!;
  var client = await DaemonClient.connect(endpoint);
  String? runId;
  try {
    final run = await DaemonAgentRun.launch(client, provider: AgentProvider.codex, host: wsl ? AgentHost.wsl : AgentHost.windows, cwd: cwd);
    runId = run.runId;
    await run.open(cwd: run.workingDirectory ?? cwd, mode: modeFor(AgentProvider.codex, PermissionMode.ask));
    unawaited(
      run
          .prompt('Dans ce dossier temporaire, crée seulement un fichier $markerName contenant ok, puis réponds terminé. Ne lis aucun autre dossier.')
          .catchError((Object error) => stdout.writeln('Le premier écran s’est déconnecté : $error')),
    );

    var seenWorking = false;
    for (var attempt = 0; attempt < 300 && run.log.pending.isEmpty; attempt++) {
      seenWorking |= run.log.working;
      if (seenWorking && !run.log.working) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (run.log.pending.isEmpty) {
      throw StateError('Aucune permission demandée ; état=${run.log.statusAt(DateTime.now())}, détail=${run.log.detail}');
    }
    final request = run.log.pending.single;
    stdout.writeln('Permission demandée : ${request.title} ; commande=${request.command}');
    await client.close();
    client = await DaemonClient.connect(endpoint);
    final again = await DaemonAgentRun.attach(client, runId, cwd: cwd);
    if (again.log.pending.length != 1 || again.log.pending.single.requestId != request.requestId) {
      throw StateError('La permission en attente n’a pas survécu à la fermeture de l’écran');
    }
    if (!again.answer(allow: false, requestId: request.requestId)) throw StateError('Le refus n’a pas été transmis');
    for (var attempt = 0; attempt < 100 && again.log.pending.isNotEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (again.log.pending.isNotEmpty) throw StateError('La demande reste en attente après refus');
    if (await markerExists()) throw StateError('Le fichier a été créé malgré le refus : $markerPath');
    stdout.writeln('Permission retrouvée après reconnexion, refus transmis, aucun fichier créé.');
  } finally {
    try {
      if (client.isClosed) client = await DaemonClient.connect(endpoint);
      if (runId != null) {
        try {
          await client.request('run.stop', {'run': runId});
        } catch (_) {
          // The run may already have ended.
        }
      }
    } finally {
      await client.close();
      await process.stdin.close();
      await process.exitCode.timeout(const Duration(seconds: 10));
      if (await markerExists()) {
        if (wsl) {
          await Process.run('wsl.exe', ['-d', 'Ubuntu', '--', 'rm', '--', markerPath]);
        } else {
          await File(markerPath).delete();
        }
      }
      await scratch?.delete();
    }
  }
}
