import 'package:mikky_engine/mikky_engine.dart';

import 'daemon/session_wire.dart';

/// A request from a Claude Code or Codex session started outside Mikky,
/// held by `mikkyd` (`daemon/mikkyd/src/hooks/mod.rs`): a permission or one
/// of Claude's questions, already in the session events' format ([event]).
/// `mikkyd` decides everything about it — whether it waits, for how long,
/// whether it can be answered here, what answers fit — the app only shows
/// it and passes the user's answer on (`hooks.answer`).
class HookAsk {
  const HookAsk({
    required this.id,
    required this.sessionId,
    required this.event,
    this.provider = AgentProvider.claude,
    this.cwd,
    this.answerable = true,
  });

  /// What `mikkyd` lists; null without a request event.
  static HookAsk? fromJson(Map<String, Object?> j) {
    final raw = j['event'];
    final event = raw is Map ? sessionEventFromWire(raw.cast<String, dynamic>()) : null;
    final id = j['id'];
    if (id is! num || (event is! PermissionAsked && event is! QuestionAsked)) return null;
    return HookAsk(
      id: id.toInt(),
      sessionId: j['sessionId'] is String ? j['sessionId']! as String : '',
      event: event!,
      provider: j['agent'] == 'codex' ? AgentProvider.codex : AgentProvider.claude,
      cwd: j['cwd'] is String ? j['cwd']! as String : null,
      answerable: j['answerable'] != false,
    );
  }

  /// `mikkyd`'s id of the request, to answer it.
  final int id;
  final String sessionId;

  /// The request: a [PermissionAsked] or a [QuestionAsked].
  final SessionEvent event;

  /// Claude Code or Codex.
  final AgentProvider provider;
  final String? cwd;

  /// False when Claude's app or VS Code asks it itself (2026-10-13): shown
  /// here, answered there; « Plus tard » only takes it off the screens.
  final bool answerable;

  bool get isQuestion => event is QuestionAsked;

  /// The user's answer: `allow`, `deny`, or null (left to the terminal).
  static String? decision({required bool? allow}) => allow == null ? null : (allow ? 'allow' : 'deny');
}
