import 'dart:async';

import 'package:mikky_engine/mikky_engine.dart';

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
List<SessionModel> offeredModels(List<SessionModel> models) => [
  for (final m in models)
    if (!'${m.id} ${m.name}'.toLowerCase().contains('haiku')) m,
];

/// One agent session Mikky drives through ACP: open it, prompt it, answer
/// its permission requests, cancel or stop it. Everything it does lands in
/// [log] (MVP spec §3.1). Rust owns the adapter;
/// `DaemonAgentRun` goes through `mikkyd`.
abstract interface class AgentRun {
  SessionLog get log;

  /// Fires after each change of [log] (and when the agent ends).
  Stream<void> get changes;

  String? get sessionId;

  /// False once the adapter has ended.
  bool get alive;

  /// The folder the adapter was started in, in its target's own form
  /// (`/tmp/x` in WSL even if the user picked `\\wsl.localhost\…\tmp\x`).
  /// The session must use this one: the agent runs its commands there.
  String? get workingDirectory;

  /// Handshake, then a new session in [cwd] — or [resume] an existing one
  /// (its thread is replayed into [log]) — then the permission [mode].
  Future<void> open({required String cwd, String? resume, String? mode});

  Future<void> setMode(String mode);

  /// Switches to [model] (one of [SessionLog.models]).
  Future<void> setModel(String model);

  /// Sends the user's message. While the agent works, it is slipped in
  /// (queued by the agent). Completes when the agent has answered it;
  /// errors are in [log], never thrown.
  Future<void> prompt(String text);

  /// Answers the oldest pending permission request (or [requestId]).
  /// [always]: the agent's « always allow » option, when it offers one (the
  /// same kind of action is then allowed without asking). Returns false if
  /// there is no request.
  bool answer({required bool allow, bool always = false, Object? requestId});

  /// Answers the pending question: [answers] by question key (a choice's
  /// label, a list of them, or free text in the question's other key).
  /// Null: the user declined to answer. Returns false if none is pending.
  bool answerQuestion(Map<String, Object>? answers);

  /// Stops the current turn; the agent stays open for the next message.
  Future<void> cancel();

  /// Ends the agent and everything it started.
  Future<void> stop();
}
