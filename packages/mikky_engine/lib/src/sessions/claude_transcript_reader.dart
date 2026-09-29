import 'session_event.dart';

/// Reads a Claude Code session file (`~/.claude/projects/<dir>/<id>.jsonl`),
/// one JSON line at a time, into [SessionEvent]s. Used for the sessions
/// started elsewhere (VS Code, terminal), which Mikky only watches.
///
/// A permission request never shows in these files: an agent waiting for
/// its user looks like an agent at work.
class ClaudeTranscriptReader {
  final Set<String> _planTools = {};
  final List<(String, PlanEntry)> _tasks = [];
  bool _started = false;
  bool _hasCwd = false;
  bool _turn = false;

  List<SessionEvent> read(Map<String, dynamic> line) {
    if (line['isSidechain'] == true) return const [];
    final at = DateTime.tryParse(line['timestamp'] as String? ?? '');
    final events = <SessionEvent>[];
    // The first lines may lack the folder: say it again once it comes.
    final sessionId = line['sessionId'] as String?;
    final cwd = line['cwd'] as String?;
    if (sessionId != null && (!_started || (!_hasCwd && cwd != null))) {
      _started = true;
      _hasCwd = cwd != null;
      events.add(SessionStarted(sessionId, cwd: cwd, at: at));
    }
    switch (line['type']) {
      case 'user':
        if (line['isMeta'] != true) _user(line, at, events);
      case 'assistant':
        _assistant(line, at, events);
      case 'attachment':
        final a = (line['attachment'] as Map?)?.cast<String, dynamic>() ?? const {};
        if (a['type'] == 'queued_command') {
          final text = _text(a['prompt']);
          if (text.isNotEmpty) events.add(UserMessage(text, queued: _turn, at: at));
        }
      case 'ai-title':
        final title = line['aiTitle'] as String?;
        if (title != null && title.isNotEmpty) events.add(TitleChanged(title, at: at));
      case 'custom-title':
        final title = line['customTitle'] as String?;
        if (title != null && title.isNotEmpty) events.add(TitleChanged(title, at: at));
    }
    return events;
  }

  void _user(Map<String, dynamic> line, DateTime? at, List<SessionEvent> events) {
    final content = (line['message'] as Map?)?['content'];
    if (content is String) return _userText(content, at, events);
    for (final b in (content as List?) ?? const []) {
      if (b is! Map) continue;
      if (b['type'] == 'tool_result') {
        final id = b['tool_use_id'] as String;
        if (_planTools.remove(id)) continue;
        events.add(ToolCallEvent(
          id,
          status: b['is_error'] == true ? ToolStatus.failed : ToolStatus.completed,
          output: _text(b['content']),
          at: at,
        ));
      } else if (b['type'] == 'text') {
        _userText(b['text'] as String? ?? '', at, events);
      }
    }
  }

  void _userText(String text, DateTime? at, List<SessionEvent> events) {
    if (text.startsWith('[Request interrupted')) {
      if (_turn) events.add(TurnEnded(StopReason.cancelled, at: at));
      _turn = false;
      return;
    }
    // Slash commands, command output and system notes, not the user's words.
    if (text.isEmpty || text.startsWith('<')) return;
    if (_turn) events.add(TurnEnded(StopReason.cancelled, at: at));
    _turn = true;
    events
      ..add(TurnStarted(at: at))
      ..add(UserMessage(text, at: at));
  }

  void _assistant(Map<String, dynamic> line, DateTime? at, List<SessionEvent> events) {
    final message = (line['message'] as Map?)?.cast<String, dynamic>() ?? const {};
    final messageId = message['id'] as String?;
    var usesTool = false;
    for (final b in (message['content'] as List?) ?? const []) {
      if (b is! Map) continue;
      switch (b['type']) {
        case 'text':
          final text = b['text'] as String? ?? '';
          if (text.isNotEmpty) events.add(AgentMessage(text, messageId: messageId, at: at));
        case 'thinking':
          final text = b['thinking'] as String? ?? '';
          if (text.isNotEmpty) events.add(AgentMessage(text, messageId: messageId, thought: true, at: at));
        case 'tool_use':
          usesTool = true;
          final plan = _plan(b['id'] as String, b['name'] as String? ?? '', (b['input'] as Map?)?.cast<String, dynamic>() ?? const {});
          if (plan != null) {
            events.add(PlanChanged(plan, at: at));
          } else {
            events.add(claudeToolCall(b['id'] as String, b['name'] as String? ?? '', (b['input'] as Map?)?.cast<String, dynamic>() ?? const {}, at: at));
          }
      }
    }
    if (line['isApiErrorMessage'] == true) {
      final text = _text(message['content']);
      final limit = text.toLowerCase().contains('limit');
      events.add(TurnEnded(limit ? StopReason.rateLimited : StopReason.error, message: text, at: at));
      _turn = false;
    } else if (message['stop_reason'] == 'end_turn' && !usesTool && _turn) {
      events.add(TurnEnded(StopReason.endTurn, at: at));
      _turn = false;
    }
  }

  /// TodoWrite, TaskCreate and TaskUpdate draw the plan instead of a tool.
  List<PlanEntry>? _plan(String id, String name, Map<String, dynamic> input) {
    switch (name) {
      case 'TodoWrite':
        _planTools.add(id);
        return [
          for (final t in (input['todos'] as List?) ?? const [])
            PlanEntry(t['content'] as String? ?? '', _status(t['status'] as String?)),
        ];
      case 'TaskCreate':
        _planTools.add(id);
        _tasks.add(('${_tasks.length + 1}', PlanEntry(input['subject'] as String? ?? '', PlanStatus.pending)));
      case 'TaskUpdate':
        _planTools.add(id);
        final taskId = '${input['taskId']}';
        final i = _tasks.indexWhere((t) => t.$1 == taskId);
        if (i < 0) return null;
        if (input['status'] == 'deleted') {
          _tasks.removeAt(i);
        } else {
          final old = _tasks[i].$2;
          _tasks[i] = (taskId, PlanEntry(input['subject'] as String? ?? old.content, input.containsKey('status') ? _status(input['status'] as String?) : old.status));
        }
      default:
        return null;
    }
    return [for (final t in _tasks) t.$2];
  }

  static PlanStatus _status(String? s) => switch (s) {
        'in_progress' => PlanStatus.inProgress,
        'completed' => PlanStatus.completed,
        _ => PlanStatus.pending,
      };

  static String _text(Object? content) {
    if (content is String) return content;
    final out = StringBuffer();
    for (final b in (content as List?) ?? const []) {
      if (b is Map && b['type'] == 'text') out.write(b['text']);
    }
    return out.toString();
  }
}

/// A Claude Code tool call as Mikky shows it: kind, title, command, diff.
ToolCallEvent claudeToolCall(String id, String name, Map<String, dynamic> input, {DateTime? at}) {
  final path = (input['file_path'] ?? input['notebook_path'] ?? input['path']) as String?;
  final file = path?.split(RegExp(r'[\\/]')).last;
  final command = input['command'] as String?;
  final kind = switch (name) {
    'Read' || 'NotebookRead' => ToolKind.read,
    'Write' || 'Edit' || 'MultiEdit' || 'NotebookEdit' => ToolKind.edit,
    'Grep' || 'Glob' || 'ToolSearch' || 'LS' => ToolKind.search,
    'WebFetch' || 'WebSearch' => ToolKind.fetch,
    'Bash' || 'PowerShell' => ToolKind.execute,
    _ => ToolKind.other,
  };
  final title = switch (name) {
    'Bash' || 'PowerShell' => command,
    'Grep' => 'grep ${input['pattern'] ?? ''}',
    'Glob' => input['pattern'] as String?,
    'WebFetch' => input['url'] as String?,
    'WebSearch' => input['query'] as String?,
    _ when file != null => '$name $file',
    _ => input['description'] as String? ?? name,
  };
  final diff = switch (name) {
    'Write' when path != null => FileDiff(path, null, input['content'] as String? ?? ''),
    'Edit' when path != null => FileDiff(path, input['old_string'] as String?, input['new_string'] as String? ?? ''),
    _ => null,
  };
  return ToolCallEvent(
    id,
    name: name,
    kind: kind,
    title: title,
    status: ToolStatus.running,
    command: command,
    path: path,
    diff: diff,
    at: at,
  );
}
