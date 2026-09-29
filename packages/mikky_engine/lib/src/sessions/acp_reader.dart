import 'session_event.dart';

/// Reads the ACP JSON-RPC stream between Mikky and an agent adapter
/// (`claude-agent-acp`, `codex-acp`), both ways, into [SessionEvent]s.
///
/// Knows the two quirks seen in the A0 probe: a prompt sent while the agent
/// works is queued, and one of the two prompts answers first (Claude answers
/// the first one at once, Codex never answers it). The turn ends when the
/// last prompt answers.
class AcpReader {
  final Map<Object, String> _methods = {};
  final Map<Object, String> _requestedModes = {};
  final Map<Object, List<PermissionOption>> _permissionOptions = {};
  final List<Object> _prompts = [];
  Object? _loading;
  bool _modeReported = false;
  bool _replayTurn = false;
  String? _lastReplayUser;

  /// True while a turn runs (a prompt is unanswered).
  bool get turnRunning => _prompts.isNotEmpty || _replayTurn;

  /// One JSON-RPC message. [outgoing]: sent by Mikky, else by the agent.
  List<SessionEvent> read(Map<String, dynamic> msg, {required bool outgoing, DateTime? at}) {
    final method = msg['method'] as String?;
    final id = msg['id'];
    final params = (msg['params'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (outgoing) {
      if (method != null) return _request(id, method, params, at);
      if (id != null && _permissionOptions.containsKey(id)) return _answer(id, msg, at);
      return const [];
    }
    if (method == 'session/update') return _update((params['update'] as Map).cast<String, dynamic>(), at);
    if (method == 'session/request_permission') return _permission(id!, params, at);
    if (method == null && id != null) return _response(id, msg, at);
    return const [];
  }

  List<SessionEvent> _request(Object? id, String method, Map<String, dynamic> params, DateTime? at) {
    if (id != null) _methods[id] = method;
    switch (method) {
      case 'session/prompt':
        final text = _text(params['prompt']);
        final queued = _prompts.isNotEmpty;
        _prompts.add(id!);
        return [
          if (!queued) TurnStarted(at: at),
          UserMessage(text, queued: queued, at: at),
        ];
      case 'session/set_mode':
        _requestedModes[id!] = params['modeId'] as String;
        _modeReported = false;
      case 'session/load':
        _loading = id;
    }
    return const [];
  }

  List<SessionEvent> _response(Object id, Map<String, dynamic> msg, DateTime? at) {
    final method = _methods.remove(id);
    final result = (msg['result'] as Map?)?.cast<String, dynamic>();
    final error = (msg['error'] as Map?)?.cast<String, dynamic>();
    switch (method) {
      case 'session/new' || 'session/load' || 'session/resume':
        final events = <SessionEvent>[];
        if (_replayTurn) {
          _replayTurn = false;
          events.add(TurnEnded(StopReason.endTurn, at: at));
        }
        if (id == _loading) _loading = null;
        if (result != null) {
          final modes = (result['modes'] as Map?)?.cast<String, dynamic>();
          events.add(SessionStarted(
            result['sessionId'] as String? ?? '',
            modes: [
              for (final m in (modes?['availableModes'] as List?) ?? const [])
                SessionMode(m['id'] as String, m['name'] as String? ?? m['id'] as String, m['description'] as String? ?? ''),
            ],
            modeId: modes?['currentModeId'] as String?,
            at: at,
          ));
        }
        return events;
      case 'session/set_mode':
        // The agent may fall back to another mode (Claude: « Auto mode
        // unavailable » with some models) and say so before answering.
        final mode = _requestedModes.remove(id);
        return [if (error == null && mode != null && !_modeReported) ModeChanged(mode, at: at)];
      case 'session/prompt':
        final i = _prompts.indexOf(id);
        if (i < 0) return const [];
        _prompts.removeRange(0, i + 1);
        if (_prompts.isNotEmpty) return const [];
        if (error != null) {
          final text = error['message'] as String? ?? 'Erreur';
          return [TurnEnded(_isLimit(text) ? StopReason.rateLimited : StopReason.error, message: text, at: at)];
        }
        return [TurnEnded(_stopReason(result?['stopReason'] as String?), at: at)];
    }
    return const [];
  }

  List<SessionEvent> _permission(Object id, Map<String, dynamic> params, DateTime? at) {
    final tool = (params['toolCall'] as Map?)?.cast<String, dynamic>() ?? const {};
    final options = [
      for (final o in (params['options'] as List?) ?? const [])
        PermissionOption(o['optionId'] as String, o['name'] as String? ?? '', o['kind'] as String? ?? ''),
    ];
    _permissionOptions[id] = options;
    final raw = (tool['rawInput'] as Map?)?.cast<String, dynamic>() ?? const {};
    return [
      PermissionAsked(
        id,
        toolCallId: tool['toolCallId'] as String?,
        title: tool['title'] as String? ?? tool['name'] as String? ?? '',
        command: _command(raw),
        options: options,
        at: at,
      ),
    ];
  }

  List<SessionEvent> _answer(Object id, Map<String, dynamic> msg, DateTime? at) {
    final options = _permissionOptions.remove(id)!;
    final outcome = ((msg['result'] as Map?)?['outcome'] as Map?)?.cast<String, dynamic>();
    final chosen = outcome?['optionId'];
    final allowed = outcome?['outcome'] == 'selected' && options.any((o) => o.id == chosen && o.allows);
    return [PermissionAnswered(id, allowed: allowed, at: at)];
  }

  List<SessionEvent> _update(Map<String, dynamic> u, DateTime? at) {
    switch (u['sessionUpdate']) {
      case 'user_message_chunk':
        final text = _text([u['content']]);
        final messageId = u['messageId'] as String?;
        if (_loading == null) return [UserMessage(text, messageId: messageId, at: at)];
        // Replay of a loaded session: each new user message is a new turn.
        final same = messageId != null && messageId == _lastReplayUser;
        _lastReplayUser = messageId;
        if (same) return [UserMessage(text, messageId: messageId, at: at)];
        final events = <SessionEvent>[
          if (_replayTurn) TurnEnded(StopReason.endTurn, at: at),
          TurnStarted(at: at),
          UserMessage(text, messageId: messageId, at: at),
        ];
        _replayTurn = true;
        return events;
      case 'agent_message_chunk' || 'agent_thought_chunk':
        final text = _text([u['content']]);
        if (text.isEmpty) return const [];
        return [
          AgentMessage(text, messageId: u['messageId'] as String?, thought: u['sessionUpdate'] == 'agent_thought_chunk', at: at),
        ];
      case 'tool_call' || 'tool_call_update':
        return [_toolCall(u, at)];
      case 'plan':
        return [
          PlanChanged([
            for (final e in (u['entries'] as List?) ?? const [])
              PlanEntry(e['content'] as String? ?? '', _planStatus(e['status'] as String?)),
          ], at: at),
        ];
      case 'current_mode_update':
        _modeReported = true;
        return [ModeChanged(u['currentModeId'] as String, at: at)];
      case 'session_info_update':
        final title = u['title'] as String?;
        return [if (title != null && title.isNotEmpty) TitleChanged(title, at: at)];
    }
    return const [];
  }

  ToolCallEvent _toolCall(Map<String, dynamic> u, DateTime? at) {
    final raw = (u['rawInput'] as Map?)?.cast<String, dynamic>() ?? const {};
    FileDiff? diff;
    String? output;
    for (final c in (u['content'] as List?) ?? const []) {
      if (c['type'] == 'diff') {
        diff = FileDiff(c['path'] as String, c['oldText'] as String?, c['newText'] as String? ?? '');
      } else if (c['type'] == 'content') {
        final t = _text([c['content']]);
        if (t.isNotEmpty) output = output == null ? t : '$output\n$t';
      }
    }
    final locations = (u['locations'] as List?) ?? const [];
    final title = u['title'] as String?;
    return ToolCallEvent(
      u['toolCallId'] as String,
      name: u['name'] as String? ?? ((u['_meta'] as Map?)?['claudeCode'] as Map?)?['toolName'] as String?,
      kind: switch (u['kind']) { final String k => _kind(k), _ => null },
      // "Preparing file…" and "Terminal" are placeholders until the real title.
      title: title == null || title.endsWith('…') || title == 'Terminal' ? null : title,
      status: _toolStatus(u['status'] as String?),
      command: _command(raw),
      path: raw['file_path'] as String? ?? (locations.isEmpty ? null : locations.first['path'] as String?),
      diff: diff,
      output: output,
      at: at,
    );
  }

  static String? _command(Map<String, dynamic> raw) => switch (raw['command']) {
        final String c => c,
        final List c => c.join(' '),
        _ => null,
      };

  static String _text(Object? blocks) {
    final out = StringBuffer();
    for (final b in (blocks as List?) ?? const []) {
      if (b is Map && b['type'] == 'text') out.write(b['text']);
    }
    return out.toString();
  }

  static ToolKind _kind(String k) => switch (k) {
        'read' => ToolKind.read,
        'edit' => ToolKind.edit,
        'delete' => ToolKind.delete,
        'move' => ToolKind.move,
        'search' => ToolKind.search,
        'execute' => ToolKind.execute,
        'think' => ToolKind.think,
        'fetch' => ToolKind.fetch,
        _ => ToolKind.other,
      };

  static ToolStatus? _toolStatus(String? s) => switch (s) {
        'pending' => ToolStatus.pending,
        'in_progress' => ToolStatus.running,
        'completed' => ToolStatus.completed,
        'failed' => ToolStatus.failed,
        _ => null,
      };

  static PlanStatus _planStatus(String? s) => switch (s) {
        'in_progress' => PlanStatus.inProgress,
        'completed' => PlanStatus.completed,
        _ => PlanStatus.pending,
      };

  static StopReason _stopReason(String? s) => switch (s) {
        'cancelled' => StopReason.cancelled,
        'refusal' => StopReason.refused,
        'max_tokens' || 'max_turn_requests' => StopReason.maxTokens,
        _ => StopReason.endTurn,
      };

  static bool _isLimit(String text) {
    final t = text.toLowerCase();
    return t.contains('rate limit') || t.contains('usage limit') || t.contains('limit reached');
  }
}
