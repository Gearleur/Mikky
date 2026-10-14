// Installs the selected tool's hooks and restarts Mikky with user approval.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';

Future<void> main(List<String> args) async {
  if ((args.length != 2 && args.length != 4) ||
      args.first != '--approved-bundle' ||
      (args.length == 4 && (args[2] != '--tool' || !['claude', 'codex'].contains(args[3])))) {
    throw ArgumentError('Usage: dart run tool/hooks_activate.dart --approved-bundle <bundle> [--tool claude|codex]');
  }
  final tool = args.length == 4 ? args[3] : 'claude';
  final bundle = Directory(args[1]).absolute.path;
  final executable = File('$bundle/mikkyd.exe');
  if (!executable.existsSync() || !File('$bundle/mikky-hook.exe').existsSync()) {
    throw StateError('Bundle incomplet.');
  }
  final known = DaemonEndpoint.fromCredentialStore();
  DaemonClient? old;
  if (known != null) {
    try {
      old = await DaemonClient.connect(known);
    } on SocketException {
      // A stale credential does not require killing any process. ensure()
      // still honours the daemon's single-instance guard when starting it.
      stdout.writeln('Ancienne adresse inactive ; aucun arrêt de processus.');
    }
    if (old != null) {
      final runs = await old.request('runs.list').timeout(const Duration(seconds: 15)) as List;
      if (runs.isNotEmpty) {
        await old.close();
        throw StateError('Des agents Mikky travaillent : mise à jour reportée.');
      }
    }
  }
  // Preview and fingerprint are made again immediately before the write.
  // This isolated daemon neither publishes credentials nor watches sessions.
  final installer = await Process.start(executable.path, ['--stdout-endpoint']);
  unawaited(installer.stderr.drain<void>());
  final endpoint = DaemonEndpoint.parse(
    await installer.stdout.transform(utf8.decoder).transform(const LineSplitter()).first,
  )!;
  final client = await DaemonClient.connect(endpoint);
  try {
    final preview = await client.request('hooks.preview', {'tool': tool}) as Map;
    final written = await client.request('hooks.write', {'tool': tool, 'fingerprint': preview['fingerprint']}) as Map;
    final status = await client.request('hooks.status', {'tool': tool}) as Map;
    if (status['installed'] != true || status['upToDate'] != true) {
      throw StateError('Installation non confirmée.');
    }
    stdout.writeln(jsonEncode({'tool': tool, 'hooks': 'installed', 'backup': written['backup']}));
  } finally {
    await client.close();
    await installer.stdin.close();
    await installer.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        installer.kill();
        return -1;
      },
    );
  }
  if (old != null) {
    final runs = await old.request('runs.list') as List;
    if (runs.isNotEmpty) {
      await old.close();
      throw StateError('Un agent Mikky a démarré : hooks installés, activation reportée.');
    }
    await old.request('daemon.shutdown').timeout(const Duration(seconds: 10));
    await old.done.timeout(const Duration(seconds: 10));
    await old.close();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final active = await DaemonClient.ensure(executable.path);
  if (active == null) throw StateError('Le nouveau moteur ne répond pas.');
  try {
    await active.request('hooks.messages.list');
    stdout.writeln(jsonEncode({'backend': 'updated', 'pid': DaemonEndpoint.fromCredentialStore()?.pid}));
  } finally {
    await active.close();
  }
}
