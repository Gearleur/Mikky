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

  /// A sub-agent's link to its parent; null for a main session.
  SubAgentLink? parent;

  String? get sessionId => log.sessionId;
}

/// Who launched a sub-agent: the parent session, the sub-agent's id (the
/// parent's tool names it, [ToolItem.agent]), the tool itself when known,
/// its name (« Front: island interactions », « Lorentz »).
class SubAgentLink {
  const SubAgentLink({required this.session, required this.agent, this.tool, this.name});

  final String session;
  final String agent;
  final String? tool;
  final String? name;

  static SubAgentLink? fromWire(Object? value) => value is Map && value['session'] is String && value['agent'] is String
      ? SubAgentLink(
          session: value['session'] as String,
          agent: value['agent'] as String,
          tool: value['tool'] as String?,
          name: value['name'] as String?,
        )
      : null;
}

/// A stream of normalized external sessions from the backend.
abstract interface class SessionWatcher {
  Map<String, WatchedSession> get sessions;
  Stream<WatchedSession> get updates;
  Future<void> start();
  Future<void> stop();
  Future<void> changed(String path);
}
