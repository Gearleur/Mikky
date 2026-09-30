import 'dart:async';

import 'package:mikky_engine/mikky_engine.dart';

import '../acp/agent_run.dart';
import 'daemon_client.dart';

/// An [AgentRun] that `mikkyd` runs (spec `2026-09-30-mikkyd-design.md`,
/// R1). `mikkyd` holds the adapter, its permission requests and questions;
/// it sends every ACP message back, which [log] reads with the same
/// [AcpReader] as a [LocalAgentRun].
class DaemonAgentRun implements AgentRun {
  DaemonAgentRun._(this._client, this.runId, this.workingDirectory) {
    _sub = _client.notifications.listen(_onNotification);
    _client.done.then((_) => _onClosed());
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

  /// Follows run [runId] of `mikkyd`: what it did so far is replayed into
  /// [log] before this completes.
  static Future<DaemonAgentRun> attach(DaemonClient client, String runId, {String? cwd}) async {
    final run = DaemonAgentRun._(client, runId, cwd);
    await client.request('run.subscribe', {'run': runId});
    return run;
  }

  final DaemonClient _client;
  final String runId;
  late final StreamSubscription<DaemonNotification> _sub;
  final AcpReader _reader = AcpReader();
  final _changes = StreamController<void>.broadcast();

  /// Requests of the agent not answered yet (seen in the traffic), oldest
  /// first: a [answer] or [answerQuestion] says at once if there was one.
  final List<Object> _asked = [];
  final List<Object> _questions = [];
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
  bool get alive => !_closed;

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
    final id = requestId ?? _asked.firstOrNull;
    if (id == null || !_asked.remove(id)) return false;
    unawaited(_client
        .request('run.answer', {'run': runId, 'allow': allow, 'always': always, 'requestId': id})
        .catchError((Object _) => null));
    return true;
  }

  @override
  bool answerQuestion(Map<String, Object>? answers) {
    if (_questions.isEmpty) return false;
    _questions.removeAt(0);
    unawaited(_client.request('run.answerQuestion', {'run': runId, 'answers': answers}).catchError((Object _) => null));
    return true;
  }

  @override
  Future<void> cancel() async {
    _asked.clear();
    _questions.clear();
    await _client.request('run.cancel', {'run': runId});
  }

  @override
  Future<void> stop() async {
    if (_closed) return;
    try {
      await _client.request('run.stop', {'run': runId});
      // `run.closed` follows once the adapter is gone.
      await _changes.stream.drain<void>().timeout(const Duration(seconds: 5));
    } catch (_) {
      // mikkyd gone: so is the agent (its job ends with mikkyd).
    }
    _onClosed();
  }

  void _onNotification(DaemonNotification n) {
    if (n.params['run'] != runId) return;
    switch (n.method) {
      case 'run.traffic':
        final message = (n.params['message'] as Map).cast<String, dynamic>();
        final outgoing = n.params['outgoing'] == true;
        final at = DateTime.tryParse(n.params['at'] as String? ?? '')?.toLocal() ?? DateTime.now();
        _track(message, outgoing: outgoing);
        log.applyAll(_reader.read(message, outgoing: outgoing, at: at));
        _changes.add(null);
      case 'run.closed':
        _onClosed();
    }
  }

  /// Keeps [_asked] and [_questions] as the agent asks and Mikky answers.
  void _track(Map<String, dynamic> message, {required bool outgoing}) {
    final id = message['id'];
    if (id == null) return;
    final method = message['method'];
    if (method == null) {
      if (outgoing) {
        _asked.remove(id);
        _questions.remove(id);
      }
    } else if (!outgoing && method == 'session/request_permission') {
      _asked.add(id as Object);
    } else if (!outgoing && method == 'elicitation/create') {
      _questions.add(id as Object);
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
