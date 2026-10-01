import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Where `mikkyd` listens (127.0.0.1) and the token it wants (spec
/// `2026-09-30-mikkyd-design.md` §5).
class DaemonEndpoint {
  const DaemonEndpoint(this.port, this.token, [this.pid]);

  final int port;
  final String token;
  final int? pid;

  /// `{"port": …, "token": …, "pid": …}`, as `mikkyd` writes it; null if
  /// it is not that.
  static DaemonEndpoint? parse(String json) {
    try {
      final m = jsonDecode(json) as Map<String, Object?>;
      return DaemonEndpoint(m['port'] as int, m['token'] as String, m['pid'] as int?);
    } catch (_) {
      return null;
    }
  }

  /// The endpoint this session's `mikkyd` put in the Windows credential
  /// store, if any (it may be gone since).
  static DaemonEndpoint? fromCredentialStore() {
    if (!Platform.isWindows) return null;
    final blob = _readCredential('Mikky/mikkyd');
    return blob == null ? null : parse(utf8.decode(blob, allowMalformed: true));
  }
}

class DaemonError implements Exception {
  DaemonError(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'DaemonError($code, $message)';
}

/// A notification from `mikkyd` (`run.traffic`, `run.closed`).
class DaemonNotification {
  const DaemonNotification(this.method, this.params);

  final String method;
  final Map<String, dynamic> params;
}

/// JSON-RPC with `mikkyd` over its WebSocket.
class DaemonClient {
  DaemonClient._(this._socket) {
    _socket.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone(), cancelOnError: true);
  }

  static Future<DaemonClient> connect(DaemonEndpoint e) async {
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${e.port}',
      headers: {'Authorization': 'Bearer ${e.token}'},
    ).timeout(const Duration(seconds: 3));
    return DaemonClient._(socket);
  }

  /// Connects to this session's `mikkyd`, starting [executable] first if
  /// none answers. Null if it cannot.
  static Future<DaemonClient?> ensure(String executable, {Duration wait = const Duration(seconds: 10)}) async {
    final known = DaemonEndpoint.fromCredentialStore();
    if (known != null) {
      try {
        final client = await connect(known);
        final hello = await client.request('hello').timeout(const Duration(seconds: 5)) as Map;
        if (hello['protocol'] == 3) return client;
        // An older idle backend can be upgraded. Never interrupt a run or
        // assume a disconnected remote machine has no work in progress.
        final runs = await client.request('runs.list').timeout(const Duration(seconds: 15)) as List;
        if (runs.isNotEmpty) return client;
        try {
          await client.request('daemon.shutdown').timeout(const Duration(seconds: 3));
        } on DaemonError catch (e) {
          if (e.code != -32601 || known.pid == null) rethrow;
          // R1 predates daemon.shutdown and is known to have no live runs.
          Process.killPid(known.pid!);
        }
        await client.close();
      } catch (_) {
        // Gone: a new one is started below.
      }
    }
    try {
      await Process.start(executable, const [], mode: ProcessStartMode.detached);
    } on ProcessException {
      return null;
    }
    // Only while it starts: it publishes its endpoint within a moment.
    final end = DateTime.now().add(wait);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final e = DaemonEndpoint.fromCredentialStore();
      if (e == null || (known != null && e.pid == known.pid && e.port == known.port)) continue;
      try {
        return await connect(e);
      } catch (_) {
        // Not listening yet.
      }
    }
    return null;
  }

  /// The `mikkyd.exe` to start: `MIKKYD` in the environment, next to
  /// Mikky's own executable, or a build of the repo's `daemon/` (dev).
  static String? findExecutable() {
    final env = Platform.environment['MIKKYD'];
    if (env != null && File(env).existsSync()) return env;
    final name = Platform.isWindows ? 'mikkyd.exe' : 'mikkyd';
    var dir = File(Platform.resolvedExecutable).parent;
    final beside = File('${dir.path}${Platform.pathSeparator}$name');
    if (beside.existsSync()) return beside.path;
    for (var i = 0; i < 8; i++) {
      for (final profile in ['release', 'debug']) {
        final f = File([dir.path, 'daemon', 'target', profile, name].join(Platform.pathSeparator));
        if (f.existsSync()) return f.path;
      }
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
    return null;
  }

  final WebSocket _socket;
  final Map<int, Completer<Object?>> _pending = {};

  /// Sync: each notification is handled before the next message, so the
  /// traffic `mikkyd` sent before an answer is in the runs' logs when the
  /// answer completes (an async stream would deliver one event per
  /// microtask, after the answer).
  final _notifications = StreamController<DaemonNotification>.broadcast(sync: true);
  final _done = Completer<void>();
  int _nextId = 0;

  Stream<DaemonNotification> get notifications => _notifications.stream;

  /// Completes when the connection ends (`mikkyd` gone, or [close]).
  Future<void> get done => _done.future;

  bool get isClosed => _done.isCompleted;

  /// Sends a request; completes with its `result`, or throws [DaemonError].
  Future<Object?> request(String method, [Map<String, Object?> params = const {}]) {
    if (isClosed) return Future.error(DaemonError(-32000, 'mikkyd gone'));
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _socket.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    return c.future;
  }

  Future<void> close() async {
    await _socket.close();
    _onDone();
  }

  void _onMessage(Object? data) {
    if (data is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(data) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final method = msg['method'] as String?;
    if (method != null) {
      _notifications.add(DaemonNotification(method, (msg['params'] as Map?)?.cast<String, dynamic>() ?? const {}));
      return;
    }
    final c = _pending.remove(msg['id']);
    if (c == null) return;
    final error = msg['error'] as Map?;
    if (error != null) {
      c.completeError(DaemonError(error['code'] as int? ?? -32000, error['message'] as String? ?? ''));
    } else {
      c.complete(msg['result']);
    }
  }

  void _onDone() {
    if (_done.isCompleted) return;
    _done.complete();
    for (final c in _pending.values) {
      c.completeError(DaemonError(-32000, 'mikkyd gone'));
    }
    _pending.clear();
    _notifications.close();
  }
}

// ------------------------------------------------ Windows credential store

/// The blob of generic credential [target], or null.
List<int>? _readCredential(String target) {
  final name = target.toNativeUtf16();
  final out = calloc<Pointer<Uint8>>();
  try {
    if (_credRead(name, _credTypeGeneric, 0, out) == 0) return null;
    final cred = out.value;
    try {
      // CREDENTIALW on 64-bit Windows: CredentialBlobSize (u32) at byte 32,
      // CredentialBlob (pointer) at byte 40.
      final size = (cred + 32).cast<Uint32>().value;
      final blob = (cred + 40).cast<Pointer<Uint8>>().value;
      return List<int>.of(blob.asTypedList(size));
    } finally {
      _credFree(cred.cast());
    }
  } finally {
    calloc.free(name);
    calloc.free(out);
  }
}

const _credTypeGeneric = 1;

final _advapi32 = DynamicLibrary.open('advapi32.dll');

final _credRead = _advapi32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Pointer<Uint8>>),
      int Function(Pointer<Utf16>, int, int, Pointer<Pointer<Uint8>>)
    >('CredReadW');
final _credFree = _advapi32.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CredFree');
