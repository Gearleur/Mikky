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

enum BackendState { connecting, online, reconnecting, unavailable }

/// The real agents inside the app: Mikky's folder on Windows and in WSL,
/// the sessions found in Claude's and Codex's files, the agents Mikky
/// launches, and who is signed in. The island and the small window both
/// read it. Nothing polls: files are watched, agents talk.
class AgentsService extends ChangeNotifier {
  AgentsService({required double Function() clock, AgentStore? store, Future<DaemonClient?> Function()? connectBackend})
    : store = store ?? AgentStore.standard(),
      _connectBackend = connectBackend ?? _defaultConnection {
    source = RealAgentSource(
      clock: clock,
      store: this.store,
      spawn: _spawn,
      deleteTranscript: (path) async {
        await _client.request('sessions.delete', {'path': path});
      },
    );
    _sub = source.changes.listen((_) => _changed());
    source.answerHook = (id, decision) {
      final client = daemon;
      if (client == null || client.isClosed) return;
      unawaited(client.request('hooks.answer', {'id': id, 'decision': decision}).catchError((Object _) => null));
    };
  }

  final AgentStore store;
  final Future<DaemonClient?> Function() _connectBackend;

  static Future<DaemonClient?> _defaultConnection() async {
    final exe = DaemonClient.findExecutable();
    if (exe == null) {
      throw StateError('Le moteur Mikky manque. Réinstalle l’application complète.');
    }
    return DaemonClient.ensure(exe);
  }

  late final RealAgentSource source;
  late final StreamSubscription<void> _sub;

  final Map<AgentHost, TargetInfo> _targets = {for (final h in AgentHost.values) h: const TargetInfo(TargetState.checking)};
  DaemonSessionWatcher? _remoteWatcher;

  /// Who is signed in, per target and tool; missing: not asked yet.
  final Map<(AgentHost, AgentProvider), AuthStatus> auth = {};

  /// Models each tool offered in its last session (for the model menu).
  final Map<AgentProvider, List<SessionModel>> models = {};

  /// `mikkyd`, which runs the agents; null: the app runs them itself.
  DaemonClient? daemon;
  BackendState backend = BackendState.connecting;
  String? backendError;
  bool _closing = false;
  Timer? _retry;
  int _attempt = 0;
  Future<void>? _connecting;
  StreamSubscription<DaemonNotification>? _backendEvents;

  bool get keepsAgents => true;
  bool get canLaunch => backend == BackendState.online;
  bool autostartEnabled = false;

  Timer? _notify;
  bool _disposed = false;

  TargetInfo target(AgentHost host) => _targets[host]!;

  /// Loads Mikky's agents, looks at both targets and starts watching their
  /// sessions. Never throws: a missing WSL is just unavailable.
  Future<void> start() async {
    store.requireRemote = true;
    _changed();
    await _connectDaemon();
  }

  /// Connects to `mikkyd` (started if needed) and takes back the agents it
  /// still runs. A failure stays explicit and schedules a reconnection.
  Future<void> _connectDaemon() => _connecting ??= _connect().whenComplete(() {
    _connecting = null;
  });

  Future<void> _connect() async {
    if (_closing || _disposed) return;
    DaemonClient? client;
    try {
      client = await _connectBackend();
      if (client == null) {
        throw StateError('Le moteur ne répond pas. Nouvelle tentative automatique.');
      }
      final hello = await client.request('hello').timeout(const Duration(seconds: 5)) as Map;
      if (hello['protocol'] != 3 || hello['persistent'] != true) {
        throw StateError('Le moteur doit être mis à jour. Arrête ses agents avant de le redémarrer.');
      }
      if (_closing || _disposed) {
        await client.close();
        return;
      }
      daemon = client;
      await _backendEvents?.cancel();
      final active = client;
      _backendEvents = client.notifications.listen((n) {
        if (n.method == 'state.changed' && daemon == active && !_closing) {
          unawaited(
            store
                .refresh()
                .then((_) async {
                  if (!_closing && !_disposed) {
                    source.restoreStored();
                    await _syncRuns(active);
                  }
                })
                .catchError((Object _) {}),
          );
        }
        if (n.method == 'hooks.changed' && daemon == active && !_closing) {
          _hookAsks(n.params['requests']);
        }
        if (n.method == 'machine.disconnected' && daemon == active && !_closing) {
          unawaited(active.close());
        }
      });
      await store.attach(client);
      source.restoreStored();
      await _remoteWatcher?.stop();
      final watcher = DaemonSessionWatcher(client);
      _remoteWatcher = watcher;
      source.follow(watcher);
      unawaited(watcher.start());
      await _syncRuns(client);
      unawaited(client.request('hooks.list').then(_hookAsks).catchError((Object _) {}));
      backend = BackendState.online;
      for (final host in AgentHost.values) {
        unawaited(_remoteTarget(client, host));
      }
      unawaited(
        client
            .request('autostart.status')
            .then((value) {
              if (!_closing && !_disposed) {
                autostartEnabled = (value as Map)['enabled'] == true;
                _changed();
              }
            })
            .catchError((Object _) {}),
      );
      backendError = null;
      _attempt = 0;
      final connected = client;
      unawaited(
        client.done.then((_) {
          if (daemon != connected || _closing || _disposed) return;
          daemon = null;
          backend = BackendState.reconnecting;
          _changed();
          _scheduleReconnect();
        }),
      );
    } catch (e) {
      if (daemon == client) daemon = null;
      await client?.close();
      backend = BackendState.unavailable;
      backendError = '$e';
      _scheduleReconnect();
    }
    _changed();
  }

  Future<void>? _syncingRuns;
  Future<void> _syncRuns(DaemonClient client) => _syncingRuns ??= _readRuns(client).whenComplete(() {
    _syncingRuns = null;
  });
  Future<void> _readRuns(DaemonClient client) async {
    final runs = await client.request('runs.list').timeout(const Duration(seconds: 15)) as List;
    final known = <String, DaemonAgentRun>{
      for (final e in source.entries)
        if (e.run case final DaemonAgentRun run) run.runId: run,
    };
    final ids = runs.map((r) => (r as Map)['run']).toSet();
    final wslUnavailable = runs.any((r) => (r as Map)['host'] == 'wsl' && r['unavailable'] == true);
    for (final e in known.entries) {
      if (wslUnavailable && e.key.startsWith('wsl:')) continue;
      if (!ids.contains(e.key)) e.value.confirmStopped();
    }
    for (final r in runs.cast<Map<String, dynamic>>()) {
      final provider = AgentProvider.values.asNameMap()[r['provider']];
      final host = AgentHost.values.asNameMap()[r['host']];
      if (provider == null || host == null || r['alive'] != true || r['sessionId'] == null) continue;
      final id = r['run'] as String;
      if (known[id] case final run?) {
        if (!run.connected) await run.reconnect(client);
        continue;
      }
      final run = await DaemonAgentRun.attach(client, id, cwd: r['cwd'] as String?, adapterPid: r['adapterPid'] as int?);
      source.adopt(run, provider: provider, host: host, cwd: r['cwd'] as String?);
    }
  }

  /// The permissions asked through Claude's hooks, as `mikkyd` lists them.
  void _hookAsks(Object? list) {
    if (list is! List) return;
    source.hookAsks([
      for (final r in list)
        if (r is Map) HookAsk.fromJson(r.cast<String, Object?>()),
    ]);
  }

  /// Claude Code's hooks for sessions started outside Mikky
  /// (`daemon/mikkyd/src/claude_settings.rs`): installed or not.
  Future<Map<String, Object?>> hooksStatus() async => ((await _client.request('hooks.status')) as Map).cast();

  /// What installing ([install]) or uninstalling would change in Claude's
  /// `settings.json`: `diff`, `changes`, `settingsPath`, `fingerprint`.
  Future<Map<String, Object?>> hooksPreview({required bool install}) async =>
      ((await _client.request('hooks.preview', {'install': install})) as Map).cast();

  /// Writes it, only if the file is still the one of [fingerprint].
  /// Returns where the old one was saved.
  Future<String?> hooksWrite({required bool install, required String fingerprint}) async {
    final r = (await _client.request('hooks.write', {'install': install, 'fingerprint': fingerprint})) as Map;
    return r['backup'] as String?;
  }

  void _scheduleReconnect() {
    if (_closing || _disposed || _retry != null) return;
    final delay = [1, 2, 4, 8, 15, 30][_attempt.clamp(0, 5)];
    _attempt++;
    _retry = Timer(Duration(seconds: delay), () {
      _retry = null;
      unawaited(_connectDaemon());
    });
  }

  Future<void> reconnect() async {
    _retry?.cancel();
    _retry = null;
    await _connectDaemon();
  }

  Future<void> _remoteTarget(DaemonClient client, AgentHost host) async {
    try {
      final status = await client.request('tools.status', {'host': host.name}) as Map;
      if (daemon != client || _closing || _disposed) return;
      _setTarget(
        host,
        status['ready'] == true
            ? const TargetInfo(TargetState.ready)
            : const TargetInfo(TargetState.checking, 'Mikky préparera les adaptateurs au premier lancement'),
      );
    } catch (e) {
      if (daemon == client && !_closing && !_disposed) {
        _setTarget(host, TargetInfo(TargetState.unavailable, '$e'));
      }
    }
  }

  DaemonClient get _client {
    final client = daemon;
    if (client == null || client.isClosed) {
      throw StateError('Le moteur est déconnecté. Attends sa reconnexion.');
    }
    return client;
  }

  Future<AgentRun> _spawn(AgentProvider provider, AgentHost host, String cwd) async {
    final client = _client;
    _setTarget(host, const TargetInfo(TargetState.installing, 'Préparation de l’agent…'));
    try {
      final run = await DaemonAgentRun.launch(client, provider: provider, host: host, cwd: cwd);
      _setTarget(host, const TargetInfo(TargetState.ready));
      run.changes.listen((_) {
        if (run.log.models.isNotEmpty) models[provider] = run.log.models;
      });
      return run;
    } catch (e) {
      _setTarget(host, TargetInfo(TargetState.unavailable, '$e'));
      rethrow;
    }
  }

  Future<AuthStatus> checkAuth(AgentHost host, AgentProvider provider) async {
    final result = await _client.request('tools.auth', {'host': host.name, 'provider': provider.name}) as Map;
    final status = AuthStatus(
      installed: result['installed'] == true,
      loggedIn: result['loggedIn'] == true,
      plan: result['plan'] as String?,
    );
    auth[(host, provider)] = status;
    _changed();
    return status;
  }

  Future<Login?> login(AgentHost host, AgentProvider provider) => Login.remote(_client, host, provider);
  Future<String> launch(LaunchRequest r) {
    if (!canLaunch) {
      return Future.error(StateError('Attends la connexion au moteur avant de lancer un agent.'));
    }
    return source.launch(r);
  }

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

  /// Closing an interface only detaches it; Rust owns agent lifetimes.
  Future<void> shutdown() async {
    _closing = true;
    _retry?.cancel();
    await source.detach();
    await _remoteWatcher?.stop();
    await daemon?.close();
    await _backendEvents?.cancel();
  }

  Future<void> stopAll() async => _client.request('runs.stopAll');
  Future<void> setAutostart(bool enabled) async {
    final client = daemon;
    if (client == null || client.isClosed) {
      throw StateError('Le moteur est déconnecté.');
    }
    await client.request('autostart.set', {'enabled': enabled});
    autostartEnabled = enabled;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _notify?.cancel();
    _sub.cancel();
    _backendEvents?.cancel();
    super.dispose();
  }
}
