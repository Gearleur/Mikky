import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// Where a target stands before Mikky can launch agents there.
enum TargetState {
  /// Being looked at (Node, adapters).
  checking,

  /// Installing Mikky's adapters (and, in WSL, its private Node).
  installing,

  ready,

  /// Not usable: no WSL, no Node, install failed ([TargetInfo.message]).
  unavailable,
}

class TargetInfo {
  const TargetInfo(this.state, [this.message]);

  final TargetState state;
  final String? message;
}

/// The real agents inside the app: Mikky's folder on Windows and in WSL,
/// the sessions found in Claude's and Codex's files, the agents Mikky
/// launches, and who is signed in. The island and the small window both
/// read it. Nothing polls: files are watched, agents talk.
class AgentsService extends ChangeNotifier {
  AgentsService({required double Function() clock, AgentStore? store}) : store = store ?? AgentStore.standard() {
    source = RealAgentSource(clock: clock, store: this.store, spawn: _spawn);
    _sub = source.changes.listen((_) => _changed());
  }

  final AgentStore store;
  late final RealAgentSource source;
  late final StreamSubscription<void> _sub;

  final Map<AgentHost, AgentSetup> _setups = {};
  final Map<AgentHost, TargetInfo> _targets = {for (final h in AgentHost.values) h: const TargetInfo(TargetState.checking)};
  final Map<AgentHost, Future<AgentSetup>> _preparing = {};
  final List<SessionWatcher> _watchers = [];

  /// Who is signed in, per target and tool; missing: not asked yet.
  final Map<(AgentHost, AgentProvider), AuthStatus> auth = {};

  /// Models each tool offered in its last session (for the model menu).
  final Map<AgentProvider, List<SessionModel>> models = {};

  /// `mikkyd`, which runs the agents; null: the app runs them itself.
  DaemonClient? daemon;

  Timer? _notify;
  bool _disposed = false;

  TargetInfo target(AgentHost host) => _targets[host]!;

  /// Loads Mikky's agents, looks at both targets and starts watching their
  /// sessions. Never throws: a missing WSL is just unavailable.
  Future<void> start({bool useDaemon = true}) async {
    await store.load();
    // The agents kept from before show at once, before the targets answer.
    _changed();
    if (useDaemon) await _connectDaemon();
    await Future.wait([for (final h in AgentHost.values) _startTarget(h)]);
  }

  /// Connects to `mikkyd` (started if needed) and takes back the agents it
  /// still runs. Without it, the app runs agents itself.
  Future<void> _connectDaemon() async {
    final exe = DaemonClient.findExecutable();
    if (exe == null) {
      debugPrint('mikky: no mikkyd found, agents run in the app');
      return;
    }
    final client = await DaemonClient.ensure(exe);
    if (client == null) {
      debugPrint('mikky: mikkyd does not answer, agents run in the app');
      return;
    }
    daemon = client;
    // Gone (it crashed): its agents went with it; new ones run in the app.
    unawaited(client.done.then((_) {
      if (daemon == client) daemon = null;
    }));
    try {
      final runs = await client.request('runs.list') as List;
      for (final r in runs.cast<Map<String, dynamic>>()) {
        final provider = AgentProvider.values.asNameMap()[r['provider']];
        final host = AgentHost.values.asNameMap()[r['host']];
        if (provider == null || host == null || r['alive'] != true) continue;
        final run = await DaemonAgentRun.attach(client, r['run'] as String, cwd: r['cwd'] as String?);
        source.adopt(run, provider: provider, host: host, cwd: r['cwd'] as String?);
      }
    } on DaemonError catch (e) {
      debugPrint('mikky: mikkyd runs unreadable ($e)');
    }
  }

  Future<void> _startTarget(AgentHost host) async {
    try {
      final setup = host == AgentHost.windows ? await AgentSetup.windows() : await AgentSetup.wsl();
      _setups[host] = setup;
      final status = await setup.check();
      _setTarget(host, status.ready ? const TargetInfo(TargetState.ready) : _missing(status, host));
      // In WSL the watch probe comes with the install: follow what can be.
      if (host == AgentHost.windows || status.adapters) await _watch(setup);
    } catch (e) {
      _setTarget(host, TargetInfo(TargetState.unavailable, host == AgentHost.wsl ? 'WSL ne répond pas' : '$e'));
    }
  }

  TargetInfo _missing(SetupStatus s, AgentHost host) {
    if (!s.node && host == AgentHost.windows) {
      return const TargetInfo(TargetState.unavailable, 'Node.js 22 ou plus est nécessaire sous Windows');
    }
    // Installed on first launch, with a word to the user.
    return const TargetInfo(TargetState.checking, 'Mikky installera ses adaptateurs au premier lancement');
  }

  Future<void> _watch(AgentSetup setup) async {
    if (_watchers.any((w) => w.target.host == setup.target.host)) return;
    final w = SessionWatcher.forSetup(setup);
    await w.start();
    _watchers.add(w);
    source.follow(w);
  }

  /// The setup of [host], installed if needed (first launch there).
  Future<AgentSetup> ready(AgentHost host) => _preparing[host] ??= _prepare(host).whenComplete(() {
        // A block, not `=> remove(…)`: that would return this very future,
        // which whenComplete would then wait for, forever.
        _preparing.remove(host);
      });

  Future<AgentSetup> _prepare(AgentHost host) async {
    final setup = _setups[host];
    if (setup == null) throw StateError(target(host).message ?? (host == AgentHost.wsl ? 'WSL ne répond pas' : 'Windows pas prêt'));
    var status = await setup.check();
    if (!status.ready) {
      if (!status.node && host == AgentHost.windows) {
        _setTarget(host, const TargetInfo(TargetState.unavailable, 'Node.js 22 ou plus est nécessaire sous Windows'));
        throw StateError('Node.js 22 ou plus est nécessaire sous Windows');
      }
      _setTarget(host, const TargetInfo(TargetState.installing, 'Mikky installe ses adaptateurs…'));
      try {
        await setup.install();
      } catch (e) {
        _setTarget(host, const TargetInfo(TargetState.unavailable, 'L’installation a échoué'));
        rethrow;
      }
      status = await setup.check();
    }
    _setTarget(host, const TargetInfo(TargetState.ready));
    await _watch(setup);
    return setup;
  }

  Future<AgentRun> _spawn(AgentProvider provider, AgentHost host, String cwd) async {
    final setup = await ready(host);
    final run = await setup.spawn(provider, cwd: cwd, daemon: daemon);
    run.changes.listen((_) {
      final m = run.log.models;
      if (m.isNotEmpty) models[provider] = m;
    });
    return run;
  }

  /// Asks the tool who is signed in (a short process each time).
  Future<AuthStatus> checkAuth(AgentHost host, AgentProvider provider) async {
    final setup = _setups[host];
    if (setup == null) return const AuthStatus(installed: false, loggedIn: false);
    final claude = provider == AgentProvider.claude ? await setup.claudeExecutable() : null;
    final s = await authStatus(setup.target, provider, claude: claude);
    auth[(host, provider)] = s;
    _changed();
    return s;
  }

  /// Starts a sign-in (a link, and for Codex a code). Null without target.
  Future<Login?> login(AgentHost host, AgentProvider provider) async {
    final setup = _setups[host];
    return setup == null ? null : Login.start(setup.target, provider);
  }

  Future<String> launch(LaunchRequest r) => source.launch(r);

  void _setTarget(AgentHost host, TargetInfo info) {
    _targets[host] = info;
    _changed();
  }

  /// Agents talk many times a second (streamed text): the UI redraws at
  /// most every 50 ms.
  void _changed() {
    if (_disposed || _notify != null) return;
    _notify = Timer(const Duration(milliseconds: 50), () {
      _notify = null;
      if (!_disposed) notifyListeners();
    });
  }

  /// Agents at work that stop if Mikky quits.
  int get working => source.entries.where((e) => e.live && e.log.working).length;

  /// Stops every agent, the watchers, and saves.
  Future<void> shutdown() async {
    await source.stopAll();
    for (final w in _watchers) {
      await w.stop();
    }
    await daemon?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _notify?.cancel();
    _sub.cancel();
    super.dispose();
  }
}
