import 'dart:async';

import 'package:mikky_engine/mikky_engine.dart';

import '../acp/agent_run.dart';
import 'daemon_client.dart';
import 'session_wire.dart';

/// An [AgentRun] that `mikkyd` runs (spec `2026-09-30-mikkyd-design.md`,
/// R1). `mikkyd` holds the adapter, its permission requests and questions;
/// it sends every ACP message back, which [log] reads with the same
/// [AcpReader] as a [LocalAgentRun].
class DaemonAgentRun implements AgentRun {
  DaemonAgentRun._(this._client, this.runId, this.workingDirectory) {
    _listen();
  }

  /// Starts `executable args` on [host] (in [cwd], a path of that host)
  /// through `mikkyd`.
  static Future<DaemonAgentRun> start(
    DaemonClient client, {
    required AgentProvider provider,
    required AgentHost host,
    required String executable,
    required List<String> args,
    required String cwd,
    Map<String, String> env = const {},
  }) async {
    final r = await client.request('run.start', {
      'provider': provider.name,
      'host': host.name,
      'executable': executable,
      'args': args,
      'cwd': cwd,
      'env': env,
    }) as Map;
    return attach(client, r['run'] as String, cwd: cwd);
  }

  /// Production launch: the backend discovers and prepares its own tools.
  static Future<DaemonAgentRun> launch(
    DaemonClient client, {
    required AgentProvider provider,
    required AgentHost host,
    required String cwd,
  }) async {
    final result = await client.request('tools.launch', {'provider': provider.name, 'host': host.name, 'cwd': cwd}) as Map;
    return attach(client, result['run'] as String, cwd: result['cwd'] as String? ?? cwd);
  }

  /// Follows run [runId] of `mikkyd`: what it did so far is replayed into
  /// [log] before this completes.
  static Future<DaemonAgentRun> attach(DaemonClient client, String runId, {String? cwd}) async {
    final run = DaemonAgentRun._(client, runId, cwd);
    await run._subscribe();
    return run;
  }

  DaemonClient _client;
  final String runId;
  late StreamSubscription<DaemonNotification> _sub;
  int _sequence = 0;

  bool get connected => !_client.isClosed && !_closed;
  bool get disconnected => _client.isClosed && !_closed;
  bool get stopped => _closed;

  void _listen() {
    final client = _client;
    _sub = client.notifications.listen(_onNotification);
    client.done.then((_) {
      // Losing a screen's socket is not evidence that an agent stopped.
      if (_client == client && !_closed) _changes.add(null);
    });
  }

  Future<void> reconnect(DaemonClient client) async {
    if (_closed) return;
    await _sub.cancel();
    _client = client;
    _listen();
    await _subscribe();
    if (!_closed) _changes.add(null);
  }

  /// Called only after a successful inventory confirms the run is gone.
  void confirmStopped() => _onClosed();

  Future<void> _subscribe() async {
    var more = true;
    while (more && !_closed) {
      final result = await _client.request('run.subscribe', {'run': runId, 'after': _sequence});
      more = result is Map && result['more'] == true;
    }
  }

  final _changes = StreamController<void>.broadcast();

  /// Requests of the agent not answered yet (seen in the traffic), oldest
  /// first: a [answer] or [answerQuestion] says at once if there was one.
  final List<Object> _asked = [];
  final List<Object> _questions = [];
  final Set<Object> _answering = {};
  bool _closed = false;

  @override
  final String? workingDirectory;

  @override
  final SessionLog log = SessionLog();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  String? get sessionId => log.sessionId;

  @override
  bool get alive => connected;

  @override
  Future<void> open({required String cwd, String? resume, String? mode}) async {
    await _client.request('run.open', {'run': runId, 'cwd': cwd, 'resume': resume, 'mode': mode});
  }

  Future<Object?> _agent(String method, Map<String, Object?> params) =>
      _client.request('run.request', {'run': runId, 'method': method, 'params': params});

  @override
  Future<void> setMode(String mode) async {
    await _agent('session/set_mode', {'sessionId': log.sessionId, 'modeId': mode});
  }

  @override
  Future<void> setModel(String model) async {
    final option = log.modelOption;
    if (option != null) {
      await _agent('session/set_config_option', {'sessionId': log.sessionId, 'configId': option, 'value': model});
    } else {
      await _agent('session/set_model', {'sessionId': log.sessionId, 'modelId': model});
    }
  }

  @override
  Future<void> prompt(String text) async {
    try {
      await _client.request('run.prompt', {'run': runId, 'text': text});
    } on DaemonError catch (_) {
      // The reader turned the error answer into TurnEnded(error).
    }
  }

  @override
  bool answer({required bool allow, bool always = false, Object? requestId}) {
    if (!connected) return false;
    final id = requestId ?? _asked.firstOrNull;
    if (id == null || !_asked.contains(id) || !_answering.add(id)) return false;
    unawaited(
      _client
          .request('run.answer', {'run': runId, 'allow': allow, 'always': always, 'requestId': id})
          .catchError((Object _) => null)
          .whenComplete(() => _answering.remove(id)),
    );
    return true;
  }

  @override
  bool answerQuestion(Map<String, Object>? answers) {
    if (!connected) return false;
    if (_questions.isEmpty) return false;
    final id = _questions.first;
    if (!_answering.add(id)) return false;
    unawaited(
      _client
          .request('run.answerQuestion', {'run': runId, 'answers': answers})
          .catchError((Object _) => null)
          .whenComplete(() => _answering.remove(id)),
    );
    return true;
  }

  @override
  Future<void> cancel() async {
    await _client.request('run.cancel', {'run': runId});
  }

  @override
  Future<void> stop() async {
    if (_closed) return;
    // A disconnected Windows hub does not prove a Linux agent has stopped.
    // Only acknowledge the stop after the owning backend confirms it.
    await _client.request('run.stop', {'run': runId});
    _onClosed();
  }

  void _onNotification(DaemonNotification n) {
    if (n.params['run'] != runId) return;
    switch (n.method) {
      case 'run.traffic':
        final sequence = n.params['sequence'] as int? ?? _sequence + 1;
        if (sequence <= _sequence) return;
        for (final value in n.params['events'] as List) {
          final event = sessionEventFromWire((value as Map).cast<String, dynamic>());
          if (event == null) continue;
          switch (event) {
            case PermissionAsked():
              _asked.add(event.requestId);
            case PermissionAnswered():
              _asked.remove(event.requestId);
            case QuestionAsked():
              _questions.add(event.requestId);
            case QuestionAnswered():
              _questions.remove(event.requestId);
            default:
              break;
          }
          log.apply(event);
        }
        _sequence = sequence;
        _changes.add(null);
      case 'run.closed':
        _onClosed();
    }
  }

  void _onClosed() {
    if (_closed) return;
    _closed = true;
    _asked.clear();
    _questions.clear();
    if (log.working) {
      log.apply(TurnEnded(StopReason.error, message: "L'agent s'est arrêté", at: DateTime.now()));
    }
    _sub.cancel();
    _changes.add(null);
    _changes.close();
  }
}
