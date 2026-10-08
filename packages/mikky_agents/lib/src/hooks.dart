import 'package:mikky_engine/mikky_engine.dart';

/// What a hook request asks.
enum HookKind {
  /// May the session use a tool (yes, no, or the terminal).
  permission,

  /// Claude's question tool (`AskUserQuestion`): choices to pick.
  question,
}

/// A request from a Claude Code or Codex session started outside Mikky (a
/// terminal, VS Code), through Mikky's hooks (`daemon/mikkyd/src/hooks.rs`):
/// a permission, or one of Claude's questions. It waits on `mikkyd` until
/// the user answers (105 s for a permission, 120 s for a question); then
/// Claude asks in its own terminal.
class HookAsk {
  const HookAsk({
    required this.id,
    required this.sessionId,
    required this.tool,
    required this.title,
    this.kind = HookKind.permission,
    this.provider = AgentProvider.claude,
    this.cwd,
    this.command,
    this.path,
    this.description,
    this.questions = const [],
    this.at,
  });

  /// What `mikkyd` lists; a field of an unexpected type is left out.
  factory HookAsk.fromJson(Map<String, Object?> j) {
    String? text(String key) => j[key] is String ? j[key]! as String : null;
    final kind = j['kind'] == 'question' ? HookKind.question : HookKind.permission;
    return HookAsk(
      id: (j['id'] as num).toInt(),
      sessionId: text('sessionId') ?? '',
      tool: text('tool') ?? '',
      title: text('title') ?? '',
      kind: kind,
      provider: j['agent'] == 'codex' ? AgentProvider.codex : AgentProvider.claude,
      cwd: text('cwd'),
      command: text('command'),
      path: text('path'),
      description: text('description'),
      questions: kind == HookKind.question ? _questions(j['questions']) : const [],
      at: DateTime.tryParse(text('at') ?? ''),
    );
  }

  /// Claude's questions as the engine shows ACP's ([Question]): key `q1`,
  /// `q2`…, the free text (« Autre ») in `q1_custom`, like ACP's forms.
  static List<Question> _questions(Object? list) {
    if (list is! List) return const [];
    return [
      for (final (i, q) in list.whereType<Map<Object?, Object?>>().indexed)
        Question(
          'q${i + 1}',
          text: q['question'] is String ? q['question']! as String : '',
          title: q['header'] is String && (q['header']! as String).isNotEmpty ? q['header']! as String : null,
          multiple: q['multiSelect'] == true,
          otherKey: 'q${i + 1}_custom',
          choices: [
            for (final o in (q['options'] is List ? q['options']! as List : const []).whereType<Map<Object?, Object?>>())
              if (o['label'] is String)
                QuestionChoice(o['label']! as String, o['description'] is String ? o['description']! as String : ''),
          ],
        ),
    ];
  }

  /// `mikkyd`'s id of the request, to answer it.
  final int id;
  final String sessionId;

  /// Claude's tool (Bash, Edit, Write, WebFetch…; AskUserQuestion).
  final String tool;

  /// One line: the tool and its command or file; a question's first text.
  final String title;

  final HookKind kind;

  /// Claude Code or Codex.
  final AgentProvider provider;
  final String? cwd;
  final String? command;
  final String? path;

  /// What Claude says the command does, if it said.
  final String? description;

  /// A question's questions (1 to 4), each with its choices.
  final List<Question> questions;
  final DateTime? at;

  bool get isQuestion => kind == HookKind.question;

  /// What the user says yes to: the command, else the file, else the line.
  /// For a question: its text.
  String get request {
    final c = command;
    if (c != null && c.trim().isNotEmpty) return c.trim();
    final p = path;
    if (p != null && p.isNotEmpty) return '$tool $p';
    return title;
  }

  /// The question as the same card shows an ACP one ([SessionLog.question]);
  /// null for a permission.
  QuestionAsked? get question => isQuestion && questions.isNotEmpty
      ? QuestionAsked('hook:$id', message: questions.length == 1 ? questions.first.text : title, questions: questions, at: at)
      : null;

  /// The card's answers (by [Question.key], free text by
  /// [Question.otherKey]) as Claude takes them: by question text, a label or
  /// the free text (a string), several labels (a list) for a multiple
  /// choice. Null when a question is left unanswered.
  Map<String, Object>? answersFor(Map<String, Object> picked) {
    final out = <String, Object>{};
    for (final q in questions) {
      final other = picked[q.otherKey];
      final value = picked[q.key];
      if (other is String && other.trim().isNotEmpty) {
        out[q.text] = other.trim();
      } else if (value is String && value.trim().isNotEmpty) {
        out[q.text] = q.multiple ? [value] : value;
      } else if (value is List && value.isNotEmpty && value.every((v) => v is String)) {
        final labels = value.cast<String>().toSet().toList();
        out[q.text] = q.multiple ? labels : labels.first;
      } else {
        return null;
      }
    }
    return out;
  }

  /// The user's answer: `allow`, `deny`, or null (left to the terminal).
  static String? decision({required bool? allow}) => allow == null ? null : (allow ? 'allow' : 'deny');
}
