import 'package:mikky_engine/mikky_engine.dart';

/// Version 1 of the normalized transcript events returned by mikkyd.
SessionEvent? sessionEventFromWire(Map<String, dynamic> e) {
  final at = DateTime.tryParse(e['at'] as String? ?? '');
  final diff = e['diff'] as Map?;
  return switch (e['type']) {
    'session' => SessionStarted(
      e['id'] as String,
      cwd: e['cwd'] as String?,
      modes: [for (final m in e['modes'] as List? ?? []) SessionMode(m['id'] as String, m['name'] as String, m['description'] as String)],
      modeId: e['modeId'] as String?,
      models: [
        for (final m in e['models'] as List? ?? []) SessionModel(m['id'] as String, m['name'] as String, m['description'] as String),
      ],
      modelId: e['modelId'] as String?,
      modelOption: e['modelOption'] as String?,
      app: AgentApp.fromWire(e['app'] as String?),
      at: at,
    ),
    'mode' => ModeChanged(e['id'] as String, at: at),
    'model' => ModelChanged(e['id'] as String, at: at),
    'tokens' => TokensUsed(
      input: (e['input'] as num).toInt(),
      output: (e['output'] as num).toInt(),
      cached: (e['cached'] as num).toInt(),
      at: at,
    ),
    'commands' => CommandsChanged([
      for (final c in e['commands'] as List)
        AgentCommand(c['name'] as String, description: c['description'] as String, hint: c['hint'] as String?),
    ], at: at),
    'permission' => PermissionAsked(
      e['id'] as Object,
      toolCallId: e['toolCallId'] as String?,
      title: e['title'] as String,
      command: e['command'] as String?,
      options: [
        for (final o in e['options'] as List)
          PermissionOption(o['optionId'] as String, o['name'] as String? ?? '', o['kind'] as String? ?? ''),
      ],
      at: at,
    ),
    'permissionAnswered' => PermissionAnswered(e['id'] as Object, allowed: e['allowed'] == true, at: at),
    'question' => QuestionAsked(
      e['id'] as Object,
      message: e['message'] as String,
      questions: [
        for (final q in e['questions'] as List)
          Question(
            q['key'] as String,
            text: q['text'] as String,
            title: q['title'] as String?,
            multiple: q['multiple'] == true,
            otherKey: q['otherKey'] as String?,
            choices: [for (final c in q['choices'] as List) QuestionChoice('${c['value']}', c['description'] as String)],
          ),
      ],
      at: at,
    ),
    'questionAnswered' => QuestionAnswered(e['id'] as Object, at: at),
    'start' => TurnStarted(at: at),
    'end' => TurnEnded(StopReason.values.byName(e['reason'] as String), message: e['message'] as String?, at: at),
    'title' => TitleChanged(e['title'] as String, at: at),
    'user' => UserMessage(e['text'] as String, messageId: e['id'] as String?, queued: e['queued'] == true, at: at),
    'message' => AgentMessage(e['text'] as String, messageId: e['id'] as String?, thought: e['thought'] == true, at: at),
    'plan' => PlanChanged([
      for (final p in e['entries'] as List) PlanEntry(p['content'] as String, PlanStatus.values.byName(p['status'] as String)),
    ], at: at),
    'context' => ContextUsed((e['used'] as num).toInt(), (e['size'] as num).toInt(), at: at),
    'limits' => LimitsSeen(
      short: _window(e['limits']['primary']),
      long: _window(e['limits']['secondary']),
      plan: e['limits']['plan_type'] as String?,
      at: at,
    ),
    'tool' => ToolCallEvent(
      e['id'] as String,
      name: e['name'] as String?,
      kind: e['kind'] == null ? null : ToolKind.values.byName(e['kind'] as String),
      title: e['title'] as String?,
      status: e['status'] == null ? null : ToolStatus.values.byName(e['status'] as String),
      command: e['command'] as String?,
      path: e['path'] as String?,
      output: e['output'] as String?,
      diff: diff == null ? null : FileDiff(diff['path'] as String, diff['old'] as String?, diff['new'] as String),
      at: at,
    ),
    _ => null,
  };
}

LimitWindow? _window(dynamic value) {
  if (value is! Map || value['used_percent'] is! num) return null;
  return LimitWindow(
    (value['used_percent'] as num).toDouble(),
    minutes: (value['window_minutes'] as num?)?.toInt() ?? 0,
    resetsAt: value['resets_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((value['resets_at'] as num).toInt() * 1000),
  );
}
