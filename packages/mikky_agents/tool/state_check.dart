// Read-only comparison of the compact island and the session list.
// Does not print prompts, paths, titles or credentials.
import 'dart:async';
import 'dart:convert';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

Future<void> main() async {
  final endpoint = DaemonEndpoint.fromCredentialStore();
  if (endpoint == null) throw StateError('No running backend');
  final client = await DaemonClient.connect(endpoint);
  final watcher = DaemonSessionWatcher(client);
  final store = AgentStore.standard();
  try {
    await store.attach(client);
    final watch = Stopwatch()..start();
    double clock() => watch.elapsedMicroseconds / 1e6;
    final source = RealAgentSource(clock: clock, store: store,
      spawn: (_, _, _) => throw StateError('Read-only diagnostic'));
    source.follow(watcher);
    await watcher.start();
    await Future<void>.delayed(const Duration(seconds: 2));
    source.advance(clock());
    final island = source.agents;
    final now = DateTime.now();
    final codex = source.limitsOf(AgentProvider.codex);
    print(jsonEncode({
      'sessions': source.homeEntries.length,
      'codexLimits': codex == null
          ? null
          : {'short': codex.short?.usedPercent, 'long': codex.long?.usedPercent, 'resets': codex.short?.resetsAt?.toIso8601String()},
      'island': [for (final a in island) {
        'id': a.id, 'status': a.status.name, 'origin': a.origin.name,
        'homeGroup': homeGroupOf(source.entry(a.id)!.homeStatus, source.entry(a.id)!.lastActivity, now).name,
        'ageMinutes': now.difference(source.entry(a.id)!.lastActivity).inMinutes,
      }],
    }));
  } finally {
    await watcher.stop();
    await client.close();
  }
}
