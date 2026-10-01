// A2 check on the real machine: setup, sign-in, watching, and one real
// Claude and Codex launched through RealAgentSource. Costs two tiny prompts.
//
// dart run tool/smoke.dart [--daemon] <windows-folder> <wsl-folder>
// --daemon: through mikkyd (a build of daemon/, started as the app does).
import 'dart:async';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart' hide SessionWatcher, WatchedSession;

import 'legacy/legacy.dart';

import 'package:mikky_engine/mikky_engine.dart';

Future<void> main(List<String> all) async {
  final watch = Stopwatch()..start();
  void say(String s) => stdout.writeln('[${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $s');
  final args = [
    for (final a in all)
      if (!a.startsWith('--')) a,
  ];
  DaemonClient? daemon;
  if (all.contains('--daemon')) {
    daemon = await DaemonClient.ensure(File('../../daemon/target/debug/mikkyd.exe').absolute.path);
    if (daemon == null) {
      say('mikkyd ne répond pas');
      exit(1);
    }
    say('mikkyd : ${await daemon.request('hello')}');
  }

  final setups = {AgentHost.windows: await AgentSetup.windows(), AgentHost.wsl: await AgentSetup.wsl()};
  for (final s in setups.values) {
    var status = await s.check();
    say('${s.target.host.name}: node ${status.nodeVersion} ok=${status.node}, adaptateurs ${status.adapters}');
    if (!status.adapters) {
      say('  installation dans ${s.dir}…');
      await s.install();
      status = await s.check();
      say('  après : prêt=${status.ready}');
    }
    for (final p in AgentProvider.values) {
      final claude = p == AgentProvider.claude ? await s.claudeExecutable() : null;
      say('  ${p.name} : ${await authStatus(s.target, p, claude: claude)}');
    }
  }

  final watchers = [for (final s in setups.values) SessionWatcher.forSetup(s, since: const Duration(days: 1))];
  final events = <AgentHost, int>{};
  for (final w in watchers) {
    await w.start();
    w.updates.listen((s) => events[s.host] = (events[s.host] ?? 0) + 1);
    say('surveillance ${w.target.host.name} : ${w.sessions.length} sessions du dernier jour');
  }

  final source = RealAgentSource(
    clock: () => watch.elapsedMilliseconds / 1000,
    spawn: (provider, host, cwd) => setups[host]!.spawn(provider, cwd: cwd, daemon: daemon),
  );
  for (final w in watchers) {
    source.follow(w);
  }
  final before = source.entries.length;
  source.changes.listen((_) {});

  final ids = [
    await source.launch(
      LaunchRequest(
        provider: AgentProvider.claude,
        host: AgentHost.wsl,
        cwd: args[1],
        prompt: 'Essai de Mikky : réponds juste « ok ».',
        model: 'sonnet',
      ),
    ),
    await source.launch(
      LaunchRequest(provider: AgentProvider.codex, host: AgentHost.windows, cwd: args[0], prompt: 'Essai de Mikky : réponds juste « ok ».'),
    ),
  ];
  for (final id in ids) {
    final e = source.entry(id)!;
    for (var i = 0; i < 240 && e.status != AgentStatus.finished && e.status != AgentStatus.error; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    say(
      '${e.provider.name} ${e.host.name} : ${e.status.name} « ${e.log.detail} » session ${e.sessionId} mode ${e.log.modeId} modèle ${e.log.modelId} ; proposés ${offeredModels(e.log.models).map((m) => m.id).take(6).join(', ')}',
    );
  }
  // Give the watchers time to see the two new session files.
  await Future<void>.delayed(const Duration(seconds: 3));
  final external = source.entries.where(
    (e) => e.origin == AgentOrigin.external && ids.every((id) => e.sessionId != source.entry(id)!.sessionId),
  );
  say(
    'entrées : ${source.entries.length} (avant les lancements : $before) ; doublons des deux lancements : ${source.entries.length - before - 2}',
  );
  say('sessions extérieures suivies : ${external.length} ; événements de fichiers : $events');
  if (daemon != null) say('mikkyd, avant l’arrêt : ${await daemon.request('runs.list')}');
  await source.stopAll();
  if (daemon != null) {
    say('mikkyd, après : ${await daemon.request('runs.list')}');
    await daemon.close();
  }
  for (final w in watchers) {
    await w.stop();
  }
  say('fini');
  exit(0);
}
