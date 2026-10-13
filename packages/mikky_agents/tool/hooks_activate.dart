// Mutates Claude settings and restarts Mikky: only with the user's approval.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2 || args.first != '--approved-bundle') {
    throw ArgumentError('Usage: dart run tool/hooks_activate.dart --approved-bundle <bundle>');
  }
  final bundle = Directory(args.last).absolute.path;
  final executable = File('$bundle/mikkyd.exe');
  if (!executable.existsSync() || !File('$bundle/mikky-hook.exe').existsSync()) {
    throw StateError('Bundle incomplet.');
  }
  final known = DaemonEndpoint.fromCredentialStore();
  DaemonClient? old;
  if (known != null) {
    old = await DaemonClient.connect(known);
    final runs = await old.request('runs.list').timeout(const Duration(seconds: 15)) as List;
    if (runs.isNotEmpty) {
      await old.close();
      throw StateError('Des agents Mikky travaillent : mise à jour reportée.');
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
    final preview = await client.request('hooks.preview', {'tool': 'claude'}) as Map;
    final written =
        await client.request('hooks.write', {'tool': 'claude', 'fingerprint': preview['fingerprint']}) as Map;
    final status = await client.request('hooks.status', {'tool': 'claude'}) as Map;
    if (status['installed'] != true || status['upToDate'] != true) {
      throw StateError('Installation non confirmée.');
    }
    stdout.writeln(jsonEncode({'claudeHooks': 'installed', 'backup': written['backup']}));
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
