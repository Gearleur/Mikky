import 'dart:async';
import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';
import 'package:mikky_agents/src/acp/agent_run.dart';

import 'target.dart';
import 'acp_connection.dart';
import '../../../mikky_engine/test/support/readers/acp_reader.dart';

/// An [AgentRun] that talks to the adapter itself, on its stdin / stdout.
class LocalAgentRun implements AgentRun {
  LocalAgentRun._(this._connection, [this._process, this._target, this.workingDirectory]) {
    _connection.onRequest = _onRequest;
    _traffic = _connection.traffic.listen((t) {
      log.applyAll(_reader.read(t.message, outgoing: t.outgoing, at: t.at));
      _changes.add(null);
    });
    _connection.done.then((_) => _onClosed());
  }

  /// Talks to an agent already connected on [input] / [output] (tests).
  factory LocalAgentRun.connect(Stream<List<int>> input, StreamSink<List<int>> output) => LocalAgentRun._(AcpConnection(input, output));

  /// Starts the adapter [executable] on [target] and connects to it.
  static Future<LocalAgentRun> spawn(
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
    return LocalAgentRun._(AcpConnection(process.stdout, process.stdin), process, target, cwd);
  }

  final AcpConnection _connection;
  final Process? _process;
  final Target? _target;

  @override
  final String? workingDirectory;
  final AcpReader _reader = AcpReader();
  @override
  final SessionLog log = SessionLog();
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<AcpTraffic> _traffic;
  final Map<Object, (List<PermissionOption>, Completer<Object?>)> _asked = {};
  final Map<Object, Completer<Object?>> _questions = {};
  bool _closed = false;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  String? get sessionId => log.sessionId;

  @override
  bool get alive => !_closed;

  @override
  Future<void> open({required String cwd, String? resume, String? mode}) async {
    await _connection.request('initialize', {
      'protocolVersion': 1,
      'clientCapabilities': {
        'fs': {'readTextFile': false, 'writeTextFile': false},
        'terminal': false,
        // Mikky shows forms: Claude may then use its question tool (the
        // adapter forbids it to clients without this).
        'elicitation': {'form': <String, Object?>{}},
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

  @override
  Future<void> setMode(String mode) async {
    await _connection.request('session/set_mode', {'sessionId': log.sessionId, 'modeId': mode});
  }

  @override
  Future<void> setModel(String model) async {
    final option = log.modelOption;
    if (option != null) {
      await _connection.request('session/set_config_option', {'sessionId': log.sessionId, 'configId': option, 'value': model});
    } else {
      await _connection.request('session/set_model', {'sessionId': log.sessionId, 'modelId': model});
    }
  }

  @override
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

  @override
  bool answer({required bool allow, bool always = false, Object? requestId}) {
    final id = requestId ?? (_asked.isEmpty ? null : _asked.keys.first);
    final asked = id == null ? null : _asked.remove(id);
    if (asked == null) return false;
    final (options, done) = asked;
    final wanted = allow ? (always ? ['allow_always', 'allow_once'] : ['allow_once', 'allow_always']) : ['reject_once', 'reject_always'];
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

  @override
  bool answerQuestion(Map<String, Object>? answers) {
    if (_questions.isEmpty) return false;
    final id = _questions.keys.first;
    final done = _questions.remove(id)!;
    done.complete(answers == null ? {'action': 'decline'} : {'action': 'accept', 'content': answers});
    return true;
  }

  @override
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
    for (final done in _questions.values) {
      done.complete({'action': 'cancel'});
    }
    _questions.clear();
  }

  @override
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
    if (method == 'elicitation/create' && params['mode'] == 'form') {
      // Same id as the QuestionAsked the reader put in [log].
      final done = Completer<Object?>();
      _questions[id] = done;
      return done.future;
    }
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
      if (!done.isCompleted) {
        done.complete({
          'outcome': {'outcome': 'cancelled'},
        });
      }
    }
    _asked.clear();
    for (final done in _questions.values) {
      if (!done.isCompleted) done.complete({'action': 'cancel'});
    }
    _questions.clear();
    if (log.working) {
      log.apply(TurnEnded(StopReason.error, message: "L'agent s'est arrêté", at: DateTime.now()));
    }
    _traffic.cancel();
    _changes.add(null);
    _changes.close();
  }
}
