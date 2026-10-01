// Isolated Windows release probe: no agents, no persistent state, no credentials.
// Usage: dart run tool/backend_perf.dart <mikkyd.exe> [session-home]
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';

Future<Map<String, dynamic>> counters(int pid) async {
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '\$p=Get-Process -Id $pid; @{cpu=\$p.CPU; workingSet=\$p.WorkingSet64; private=\$p.PrivateMemorySize64} | ConvertTo-Json -Compress',
  ]);
  if (result.exitCode != 0) throw StateError('Cannot sample backend process');
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) throw ArgumentError('Pass a release mikkyd.exe');
  final boot = Stopwatch()..start();
  final process = await Process.start(args.first, [
    '--stdout-endpoint',
    if (args.length > 1) ...['--watch-home', args[1]],
  ]);
  final errors = process.stderr.drain<void>();
  DaemonClient? client;
  try {
    final line = await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first;
    client = await DaemonClient.connect(DaemonEndpoint.parse(line)!);
    await client.request('hello');
    final readyMs = boot.elapsedMicroseconds / 1000;
    // Allow the asynchronous initial directory scan to settle before sampling.
    await Future<void>.delayed(const Duration(seconds: 5));
    final sessions = await client.request('sessions.list') as List;
    final latencies = <double>[];
    for (var i = 0; i < 100; i++) {
      final clock = Stopwatch()..start();
      await client.request('hello');
      latencies.add(clock.elapsedMicroseconds / 1000);
    }
    latencies.sort();
    final before = await counters(process.pid);
    final idle = Stopwatch()..start();
    await Future<void>.delayed(const Duration(seconds: 5));
    final after = await counters(process.pid);
    final cpu = ((after['cpu'] as num) - (before['cpu'] as num)) / (idle.elapsedMilliseconds / 1000) * 100;
    print(
      const JsonEncoder.withIndent('  ').convert({
        'scenario': args.length > 1 ? 'native session watcher, no launched agents' : 'empty backend',
        'readyMs': readyMs,
        'sessionsAfter5s': sessions.length,
        'helloMedianMs': latencies[50],
        'helloP95Ms': latencies[94],
        'idleCpuPercentOneCore': cpu,
        'workingSetMiB': (after['workingSet'] as num) / (1024 * 1024),
        'privateMiB': (after['private'] as num) / (1024 * 1024),
        'binaryMiB': await File(args.first).length() / (1024 * 1024),
      }),
    );
  } finally {
    await client?.close();
    await process.stdin.close();
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await errors;
  }
}
