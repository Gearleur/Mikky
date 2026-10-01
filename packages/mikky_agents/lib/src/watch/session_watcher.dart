import 'dart:async';

import 'package:mikky_engine/mikky_engine.dart';

/// A session found in Claude's or Codex's files, kept up to date.
class WatchedSession {
  WatchedSession(this.path, this.provider, this.host);

  /// The file, as Windows reads it.
  final String path;
  final AgentProvider provider;
  final AgentHost host;
  final SessionLog log = SessionLog();

  /// Last write seen on the file.
  DateTime modified = DateTime.fromMillisecondsSinceEpoch(0);

  /// Id of the first user message (Claude). A resumed session (« fork »)
  /// copies the history with the same ids: sessions sharing it are one
  /// conversation.
  String? firstMessage;

  String? get sessionId => log.sessionId;
}

/// A stream of normalized external sessions from the backend.
abstract interface class SessionWatcher {
  Map<String, WatchedSession> get sessions;
  Stream<WatchedSession> get updates;
  Future<void> start();
  Future<void> stop();
  Future<void> changed(String path);
}
