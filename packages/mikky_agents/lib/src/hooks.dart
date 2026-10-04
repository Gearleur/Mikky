import 'package:mikky_engine/mikky_engine.dart';

/// A permission asked by a Claude Code or Codex session started outside
/// Mikky (a terminal, VS Code), through Mikky's hooks (`daemon/mikkyd/src/hooks.rs`).
/// It waits on `mikkyd` until the user answers, or for 105 s; then Claude
/// asks in its own terminal.
class HookAsk {
  const HookAsk({
    required this.id,
    required this.sessionId,
    required this.tool,
    required this.title,
    this.provider = AgentProvider.claude,
    this.cwd,
    this.command,
    this.path,
    this.description,
    this.at,
  });

  /// What `mikkyd` lists; a field of an unexpected type is left out.
  factory HookAsk.fromJson(Map<String, Object?> j) {
    String? text(String key) => j[key] is String ? j[key]! as String : null;
    return HookAsk(
      id: (j['id'] as num).toInt(),
      sessionId: text('sessionId') ?? '',
      tool: text('tool') ?? '',
      title: text('title') ?? '',
      provider: j['agent'] == 'codex' ? AgentProvider.codex : AgentProvider.claude,
      cwd: text('cwd'),
      command: text('command'),
      path: text('path'),
      description: text('description'),
      at: DateTime.tryParse(text('at') ?? ''),
    );
  }

  /// `mikkyd`'s id of the request, to answer it.
  final int id;
  final String sessionId;

  /// Claude's tool (Bash, Edit, Write, WebFetch…).
  final String tool;

  /// One line: the tool and its command or file.
  final String title;

  /// Claude Code or Codex.
  final AgentProvider provider;
  final String? cwd;
  final String? command;
  final String? path;

  /// What Claude says the command does, if it said.
  final String? description;
  final DateTime? at;

  /// What the user says yes to: the command, else the file, else the line.
  String get request {
    final c = command;
    if (c != null && c.trim().isNotEmpty) return c.trim();
    final p = path;
    if (p != null && p.isNotEmpty) return '$tool $p';
    return title;
  }

  /// The user's answer: `allow`, `deny`, or null (left to the terminal).
  static String? decision({required bool? allow}) => allow == null ? null : (allow ? 'allow' : 'deny');
}
