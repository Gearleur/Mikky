import 'dart:async';
import 'dart:convert';

/// One JSON-RPC message on the wire, with its direction and time: what
/// `AcpReader` reads to build the session.
class AcpTraffic {
  const AcpTraffic(this.message, {required this.outgoing, required this.at});

  final Map<String, dynamic> message;
  final bool outgoing;
  final DateTime at;
}

/// An error answer from the agent.
class AcpError implements Exception {
  AcpError(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'AcpError($code, $message)';
}

/// Answers a request from the agent (a permission request…). Throw an
/// [AcpError] to answer with an error.
typedef AcpRequestHandler = Future<Object?> Function(Object id, String method, Map<String, dynamic> params);

/// JSON-RPC 2.0 over newline-delimited JSON, as ACP uses on an agent
/// adapter's stdin / stdout. Knows nothing of ACP methods.
class AcpConnection {
  AcpConnection(Stream<List<int>> input, this._output, {this.onRequest, DateTime Function()? now}) : _now = now ?? DateTime.now {
    _input = input
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onDone, onError: (_) => _onDone());
  }

  final StreamSink<List<int>> _output;

  /// Answers the agent's requests; none: every request gets an error.
  AcpRequestHandler? onRequest;
  final DateTime Function() _now;
  late final StreamSubscription<String> _input;
  final _traffic = StreamController<AcpTraffic>.broadcast(sync: true);
  final _stderrLike = StreamController<String>.broadcast(sync: true);
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final _closed = Completer<void>();
  int _nextId = 0;

  /// Every message, both ways, in order.
  Stream<AcpTraffic> get traffic => _traffic.stream;

  /// Lines on stdout that are not JSON (logs some adapters print).
  Stream<String> get noise => _stderrLike.stream;

  /// Completes when the agent's output ends.
  Future<void> get done => _closed.future;

  bool get isClosed => _closed.isCompleted;

  /// Sends a request; completes with its `result`, or throws [AcpError].
  Future<Map<String, dynamic>> request(String method, [Map<String, dynamic> params = const {}]) {
    if (isClosed) return Future.error(AcpError(-32000, 'agent closed'));
    final id = _nextId++;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return c.future;
  }

  void notify(String method, [Map<String, dynamic> params = const {}]) {
    if (isClosed) return;
    _send({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  /// Stops reading and fails what is still waiting.
  Future<void> close() async {
    await _input.cancel();
    _onDone();
    try {
      await _output.close();
    } catch (_) {}
  }

  void _send(Map<String, dynamic> msg) {
    _traffic.add(AcpTraffic(msg, outgoing: true, at: _now()));
    try {
      _output.add(utf8.encode('${jsonEncode(msg)}\n'));
    } catch (_) {
      // The agent is gone; _onDone fails the pending requests.
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (_) {
      _stderrLike.add(line);
      return;
    }
    _traffic.add(AcpTraffic(msg, outgoing: false, at: _now()));
    final id = msg['id'];
    final method = msg['method'] as String?;
    if (method == null) {
      final c = id is int ? _pending.remove(id) : null;
      if (c == null) return;
      final error = msg['error'] as Map?;
      if (error != null) {
        c.completeError(AcpError(error['code'] as int? ?? -32000, error['message'] as String? ?? ''));
      } else {
        c.complete((msg['result'] as Map?)?.cast<String, dynamic>() ?? const {});
      }
      return;
    }
    if (id != null) _answer(id, method, (msg['params'] as Map?)?.cast<String, dynamic>() ?? const {});
  }

  Future<void> _answer(Object id, String method, Map<String, dynamic> params) async {
    final handler = onRequest;
    try {
      if (handler == null) throw AcpError(-32601, 'Method not found: $method');
      final result = await handler(id, method, params);
      if (!isClosed) _send({'jsonrpc': '2.0', 'id': id, 'result': result ?? const {}});
    } on AcpError catch (e) {
      if (!isClosed) {
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': e.code, 'message': e.message},
        });
      }
    }
  }

  void _onDone() {
    if (_closed.isCompleted) return;
    _closed.complete();
    for (final c in _pending.values) {
      c.completeError(AcpError(-32000, 'agent closed'));
    }
    _pending.clear();
  }
}
