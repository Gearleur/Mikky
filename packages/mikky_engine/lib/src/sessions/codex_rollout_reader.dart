import 'dart:convert';

import 'session_event.dart';

/// Reads a Codex session file (`~/.codex/sessions/YYYY/MM/DD/rollout-….jsonl`),
/// one JSON line at a time, into [SessionEvent]s. Codex writes an item once
/// it is done (`item_completed`), so a running command shows only when it
/// ends; `task_started` / `task_complete` frame each turn.
class CodexRolloutReader {
  bool _turn = false;
  bool _userInTurn = false;

  List<SessionEvent> read(Map<String, dynamic> line) {
    final at = DateTime.tryParse(line['timestamp'] as String? ?? '');
    final p = (line['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (line['type']) {
      case 'session_meta':
        final id = (p['id'] ?? p['session_id']) as String?;
        return [if (id != null) SessionStarted(id, cwd: p['cwd'] as String?, at: at)];
      case 'event_msg':
        return _event(p, at);
      case 'response_item':
        // Items are also written as event_msg; only the plan tool is not.
        if (p['type'] == 'function_call' && p['name'] == 'update_plan') {
          final args = jsonDecode(p['arguments'] as String? ?? '{}') as Map;
          return [_planChanged(args['plan'], at)];
        }
    }
    return const [];
  }

  List<SessionEvent> _event(Map<String, dynamic> p, DateTime? at) {
    switch (p['type']) {
      case 'task_started':
        _turn = true;
        _userInTurn = false;
        return [TurnStarted(at: at)];
      case 'task_complete':
        return _end(StopReason.endTurn, at);
      case 'turn_aborted':
        return _end(StopReason.cancelled, at);
      case 'error':
        final text = p['message'] as String? ?? 'Erreur';
        return _end(text.toLowerCase().contains('limit') ? StopReason.rateLimited : StopReason.error, at, text);
      case 'plan_update':
        return [_planChanged(p['plan'], at)];
      case 'item_completed':
        return _item((p['item'] as Map).cast<String, dynamic>(), at);
    }
    return const [];
  }

  List<SessionEvent> _end(StopReason reason, DateTime? at, [String? message]) {
    if (!_turn) return const [];
    _turn = false;
    return [TurnEnded(reason, message: message, at: at)];
  }

  List<SessionEvent> _item(Map<String, dynamic> item, DateTime? at) {
    final id = item['id'] as String? ?? '';
    switch (item['type']) {
      case 'UserMessage':
        final text = _text(item['content']);
        if (text.isEmpty) return const [];
        final queued = _userInTurn;
        _userInTurn = true;
        // Codex writes no title in this file: none is made up here, so a
        // better one (Mikky's, from ACP) wins; the app falls back to the
        // first message.
        return [UserMessage(text, queued: queued, at: at)];
      case 'AgentMessage':
        final text = _text(item['content']);
        return [if (text.isNotEmpty) AgentMessage(text, messageId: id, at: at)];
      case 'CommandExecution':
        final parsed = (item['parsed_cmd'] as List?) ?? const [];
        final command = parsed.isNotEmpty ? parsed.first['cmd'] as String? : _command(item['command']);
        return [
          ToolCallEvent(
            id,
            name: 'exec_command',
            kind: switch (parsed.isEmpty ? null : parsed.first['type']) {
              'read' => ToolKind.read,
              'search' || 'list_files' => ToolKind.search,
              _ => ToolKind.execute,
            },
            title: command,
            command: command,
            status: item['status'] == 'completed' && (item['exit_code'] ?? 0) == 0 ? ToolStatus.completed : ToolStatus.failed,
            output: item['aggregated_output'] as String?,
            at: at,
          ),
        ];
      case 'FileChange':
        final changes = (item['changes'] as Map?)?.cast<String, dynamic>() ?? const {};
        final path = changes.keys.isEmpty ? null : changes.keys.first;
        return [
          ToolCallEvent(
            id,
            name: 'apply_patch',
            kind: ToolKind.edit,
            title: path == null ? 'Modifie des fichiers' : 'Edit ${path.split(RegExp(r'[\\/]')).last}',
            path: path,
            status: item['status'] == 'failed' ? ToolStatus.failed : ToolStatus.completed,
            at: at,
          ),
        ];
      case 'WebSearch':
        return [
          ToolCallEvent(id, name: 'web_search', kind: ToolKind.fetch, title: item['query'] as String?, status: ToolStatus.completed, at: at),
        ];
    }
    return const [];
  }

  static PlanChanged _planChanged(Object? plan, DateTime? at) => PlanChanged([
        for (final s in (plan as List?) ?? const [])
          PlanEntry(s['step'] as String? ?? '', switch (s['status']) {
            'in_progress' => PlanStatus.inProgress,
            'completed' => PlanStatus.completed,
            _ => PlanStatus.pending,
          }),
      ], at: at);

  static String? _command(Object? command) => switch (command) {
        final String c => c,
        final List c => c.last as String,
        _ => null,
      };

  static String _text(Object? content) {
    final out = StringBuffer();
    for (final b in (content as List?) ?? const []) {
      if (b is Map && (b['type'] == 'text' || b['type'] == 'Text')) out.write(b['text']);
    }
    return out.toString();
  }
}
