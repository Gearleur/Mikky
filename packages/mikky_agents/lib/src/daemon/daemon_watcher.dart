import 'dart:async';

import 'package:mikky_engine/mikky_engine.dart';

import '../watch/session_watcher.dart';
import 'daemon_client.dart';
import 'session_wire.dart';

/// Presentation adapter: Rust reads and normalizes transcripts; this client
/// folds pages of shared events without opening any file or starting a probe.
class DaemonSessionWatcher implements SessionWatcher {
  DaemonSessionWatcher(this.client);
  final DaemonClient client;
  final _sessions = <String, WatchedSession>{};
  final _offsets = <String, int>{};
  final _generations = <String, int>{};
  final _updates = StreamController<WatchedSession>.broadcast();
  final _queues = <String, Future<void>>{};
  final _dirty = <String>{};
  StreamSubscription<DaemonNotification>? _sub;
  bool _stopped = false;

  @override
  Map<String, WatchedSession> get sessions => Map.unmodifiable(_sessions);
  @override
  Stream<WatchedSession> get updates => _updates.stream;

  @override
  Future<void> start() async {
    _sub = client.notifications.listen((n) {
      if (n.method != 'sessions.changed' || _stopped) return;
      if (n.params['path'] case final String path) {
        unawaited(changed(path));
      } else {
        unawaited(_scan());
      }
    });
    await _scan();
  }

  Future<void> _scan() async {
    try {
      final list = await client.request('sessions.list') as List;
      for (final s in list) {
        if (!_stopped) await changed((s as Map)['path'] as String);
      }
    } on DaemonError {
      /* Reconnection obtains a fresh inventory. */
    }
  }

  @override
  Future<void> changed(String path) {
    _dirty.add(path);
    if (_queues[path] case final active?) return active;
    final future =
        Future<void>(() async {
          while (_dirty.remove(path) && !_stopped) {
            await _read(path);
          }
        }).whenComplete(() {
          _queues.remove(path);
        });
    _queues[path] = future;
    return future;
  }

  Future<void> _read(String path) async {
    try {
      var more = true;
      while (more && !_stopped) {
        final page = await client.request('sessions.read', {
          'path': path,
          'after': _offsets[path] ?? 0,
          'generation': _generations[path] ?? 0,
        }) as Map;
        final meta = page['session'] as Map;
        final generation = meta['generation'] as int;
        final provider = AgentProvider.values.byName(meta['provider'] as String);
        if (!_sessions.containsKey(path) || _generations[path] != generation) {
          _sessions[path] = WatchedSession(path, provider, meta['host'] == 'wsl' ? AgentHost.wsl : AgentHost.windows);
          _generations[path] = generation;
        }
        final session = _sessions[path]!;
        for (final value in page['lines'] as List) {
          final line = (value as Map).cast<String, dynamic>();
          if (sessionEventFromWire(line) case final event?) {
            session.log.apply(event);
          }
        }
        session.firstMessage = meta['firstMessage'] as String?;
        session.modified = DateTime.fromMillisecondsSinceEpoch(meta['modified'] as int);
        _offsets[path] = page['next'] as int;
        more = page['more'] == true;
        if (!_stopped) _updates.add(session);
      }
    } on DaemonError {
      /* A disconnected screen does not stop watching in Rust. */
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await _sub?.cancel();
    await _updates.close();
  }
}
