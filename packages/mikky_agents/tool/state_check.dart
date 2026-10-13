// Read-only comparison of the compact island and the session list.
// Does not print prompts, paths, titles or credentials.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

Future<void> main(List<String> args) async {
  Process? probe;
  var endpoint = DaemonEndpoint.fromCredentialStore();
  if (args.contains('--isolated')) {
    final homeArg = args.indexOf('--watch-home');
    probe = await Process.start('../../daemon/target/debug/mikkyd.exe', [
      '--stdout-endpoint',
      '--watch-home',
      homeArg >= 0 ? args[homeArg + 1] : Platform.environment['USERPROFILE']!,
    ]);
    endpoint = DaemonEndpoint.parse(await probe.stdout.transform(utf8.decoder).transform(const LineSplitter()).first);
  }
  if (endpoint == null) throw StateError('No running backend');
  final client = await DaemonClient.connect(endpoint);
  final watcher = DaemonSessionWatcher(client);
  final store = AgentStore.standard();
  try {
    await store.attach(client);
    final watch = Stopwatch()..start();
    double clock() => watch.elapsedMicroseconds / 1e6;
    final source = RealAgentSource(
      clock: clock,
      store: store,
      spawn: (_, _, _) => throw StateError('Read-only diagnostic'),
    );
    source.follow(watcher);
    await watcher.start();
    await Future<void>.delayed(const Duration(seconds: 2));
    source.advance(clock());
    final island = source.agents;
    final now = DateTime.now();
    final codex = source.limitsOf(AgentProvider.codex);
    print(
      jsonEncode({
        'sessions': source.homeEntries.length,
        'subAgents': watcher.sessions.values.where((s) => s.parent != null).length,
        'childrenByProvider': {
          for (final p in AgentProvider.values)
            p.name: watcher.sessions.values.where((s) => s.parent != null && s.provider == p).length,
        },
        'attachedChildren': source.entries.fold<int>(0, (n, e) => n + e.log.subAgents.length),
        'limitedSessions': [
          for (final e in source.homeEntries)
            if (e.status == AgentStatus.rateLimited)
              {
                'provider': e.provider.name,
                'fromChild': e.log.limitSource != null && e.log.limitSource != e.log,
                'resets': e.log.limitResetsAt?.toIso8601String(),
              },
        ],
        'codexLimits': codex == null
            ? null
            : {
                'short': codex.short?.usedPercent,
                'long': codex.long?.usedPercent,
                'resets': codex.short?.resetsAt?.toIso8601String(),
              },
        'island': [
          for (final a in island)
            {
              'id': a.id,
              'status': a.status.name,
              'origin': a.origin.name,
              'homeGroup': homeGroupOf(source.entry(a.id)!.homeStatus, source.entry(a.id)!.lastActivity, now).name,
              'ageMinutes': now.difference(source.entry(a.id)!.lastActivity).inMinutes,
              'app': source.entry(a.id)!.app?.name,
            },
        ],
        // The software of the most recent sessions (what the notch shows).
        'recentApps': [
          for (final e in (source.homeEntries.toList()..sort((a, b) => b.lastActivity.compareTo(a.lastActivity))).take(
            5,
          ))
            e.app?.name,
        ],
      }),
    );
  } finally {
    await watcher.stop();
    await client.close();
    if (probe != null) {
      await probe.stdin.close();
      await probe.exitCode.timeout(const Duration(seconds: 10));
    }
  }
}
