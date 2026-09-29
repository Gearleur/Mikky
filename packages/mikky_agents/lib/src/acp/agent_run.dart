import 'dart:async';
import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';

import '../target.dart';
import 'acp_connection.dart';

/// The ACP mode for a permission choice (checked in the A0 probe):
/// Ask → Claude `default` (Manual), Codex `read-only`;
/// Auto → Claude `auto`, Codex `agent` (Auto review).
/// Never `bypassPermissions` nor `agent-full-access`.
String modeFor(AgentProvider provider, PermissionMode permissions) => switch ((provider, permissions)) {
      (AgentProvider.claude, PermissionMode.ask) => 'default',
      (AgentProvider.claude, PermissionMode.auto) => 'auto',
      (AgentProvider.codex, PermissionMode.ask) => 'read-only',
      (AgentProvider.codex, PermissionMode.auto) => 'agent',
    };

/// The models Mikky offers: all the agent's, but Haiku (decision of
/// 2026-09-29: it behaves apart, it refuses Auto for one).
List<SessionModel> offeredModels(List<SessionModel> models) =>
    [for (final m in models) if (!'${m.id} ${m.name}'.toLowerCase().contains('haiku')) m];

/// One agent session driven by Mikky through ACP: open it, prompt it,
/// answer its permission requests, cancel or stop it. Everything it does
/// lands in [log] (MVP spec §3.1).
class AgentRun {
  AgentRun._(this._connection, [this._process, this._target]) {
    _connection.onRequest = _onRequest;
    _traffic = _connection.traffic.listen((t) {
      log.applyAll(_reader.read(t.message, outgoing: t.outgoing, at: t.at));
      _changes.add(null);
    });
    _connection.done.then((_) => _onClosed());
  }

  /// Talks to an agent already connected on [input] / [output] (tests).
  factory AgentRun.connect(Stream<List<int>> input, StreamSink<List<int>> output) =>
      AgentRun._(AcpConnection(input, output));

  /// Starts the adapter [executable] on [target] and connects to it.
  static Future<AgentRun> spawn(
    Target target,
    String executable,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    final process = await target.start(executable, args, cwd: cwd, env: env);
    target.contain(process);
    // Adapters log on stderr: drained so the pipe never fills.
    process.stderr.drain<void>();
    return AgentRun._(AcpConnection(process.stdout, process.stdin), process, target);
  }

  final AcpConnection _connection;
  final Process? _process;
  final Target? _target;
  final AcpReader _reader = AcpReader();
  final SessionLog log = SessionLog();
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<AcpTraffic> _traffic;
  final Map<Object, (List<PermissionOption>, Completer<Object?>)> _asked = {};
  bool _closed = false;

  /// Fires after each change of [log] (and when the agent ends).
  Stream<void> get changes => _changes.stream;

  String? get sessionId => log.sessionId;

  /// False once the adapter has ended.
  bool get alive => !_closed;

  /// Handshake, then a new session in [cwd] — or [resume] an existing one
  /// (its thread is replayed into [log]) — then the permission [mode].
  Future<void> open({required String cwd, String? resume, String? mode}) async {
    await _connection.request('initialize', {
      'protocolVersion': 1,
      'clientCapabilities': {
        'fs': {'readTextFile': false, 'writeTextFile': false},
        'terminal': false,
      },
      'clientInfo': {'name': 'mikky', 'version': '0.1.0'},
    });
    if (resume == null) {
      await _connection.request('session/new', {'cwd': cwd, 'mcpServers': []});
    } else {
      await _connection.request('session/load', {'sessionId': resume, 'cwd': cwd, 'mcpServers': []});
    }
    if (mode != null) await setMode(mode);
  }

  Future<void> setMode(String mode) async {
    await _connection.request('session/set_mode', {'sessionId': log.sessionId, 'modeId': mode});
  }

  /// Switches to [model] (one of [SessionLog.models]).
  Future<void> setModel(String model) async {
    final option = log.modelOption;
    if (option != null) {
      await _connection.request('session/set_config_option', {'sessionId': log.sessionId, 'configId': option, 'value': model});
    } else {
      await _connection.request('session/set_model', {'sessionId': log.sessionId, 'modelId': model});
    }
  }

  /// Sends the user's message. While the agent works, it is slipped in
  /// (queued by the agent). Completes when the agent has answered it;
  /// errors are in [log], never thrown.
  Future<void> prompt(String text) async {
    try {
      await _connection.request('session/prompt', {
        'sessionId': log.sessionId,
        'prompt': [
          {'type': 'text', 'text': text},
        ],
      });
    } on AcpError catch (_) {
      // The reader turned the error answer into TurnEnded(error).
    }
  }

  /// Answers the oldest pending permission request (or [requestId]).
  /// Returns false if there is none.
  bool answer({required bool allow, Object? requestId}) {
    final id = requestId ?? (_asked.isEmpty ? null : _asked.keys.first);
    final asked = id == null ? null : _asked.remove(id);
    if (asked == null) return false;
    final (options, done) = asked;
    final wanted = allow ? ['allow_once', 'allow_always'] : ['reject_once', 'reject_always'];
    PermissionOption? pick;
    for (final kind in wanted) {
      for (final o in options) {
        if (pick == null && o.kind == kind) pick = o;
      }
    }
    done.complete({
      'outcome': pick == null ? {'outcome': 'cancelled'} : {'outcome': 'selected', 'optionId': pick.id},
    });
    return true;
  }

  /// Stops the current turn; the agent stays open for the next message.
  Future<void> cancel() async {
    _connection.notify('session/cancel', {'sessionId': log.sessionId});
    // After a cancel, ACP wants every open permission request answered
    // « cancelled ».
    for (final (_, done) in _asked.values) {
      done.complete({
        'outcome': {'outcome': 'cancelled'},
      });
    }
    _asked.clear();
  }

  /// Ends the agent and everything it started.
  Future<void> stop() async {
    if (_closed) return;
    if (log.working) await cancel();
    await _connection.close();
    final process = _process;
    if (process != null) {
      // Closing stdin ends the adapter; then the job ends what is left
      // (commands the agent ran in the background…).
      await process.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => -1);
      await (_target ?? WindowsTarget()).kill(process);
    }
    _onClosed();
  }

  Future<Object?> _onRequest(Object id, String method, Map<String, dynamic> params) {
    if (method != 'session/request_permission') {
      throw AcpError(-32601, 'Method not found: $method');
    }
    final done = Completer<Object?>();
    final options = [
      for (final o in (params['options'] as List?) ?? const [])
        PermissionOption(o['optionId'] as String, o['name'] as String? ?? '', o['kind'] as String? ?? ''),
    ];
    // Same id as the PermissionAsked the reader put in [log].
    _asked[id] = (options, done);
    return done.future;
  }

  void _onClosed() {
    if (_closed) return;
    _closed = true;
    for (final (_, done) in _asked.values) {
      if (!done.isCompleted) done.complete({'outcome': {'outcome': 'cancelled'}});
    }
    _asked.clear();
    if (log.working) {
      log.apply(TurnEnded(StopReason.error, message: "L'agent s'est arrêté", at: DateTime.now()));
    }
    _traffic.cancel();
    _changes.add(null);
    _changes.close();
  }
}
