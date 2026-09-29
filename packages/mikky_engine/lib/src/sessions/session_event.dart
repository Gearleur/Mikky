/// What happens in an agent session, whatever it came from: the live ACP
/// stream, or a Claude / Codex session file read afterwards (MVP spec §7).
/// Readers turn their format into these events; [SessionLog] folds them.
sealed class SessionEvent {
  const SessionEvent({this.at});

  /// Wall-clock time of the event, when the source gives one.
  final DateTime? at;
}

/// The session exists: its id, folder and the modes the agent offers.
class SessionStarted extends SessionEvent {
  const SessionStarted(
    this.sessionId, {
    this.cwd,
    this.modes = const [],
    this.modeId,
    this.models = const [],
    this.modelId,
    this.modelOption,
    super.at,
  });

  final String sessionId;
  final String? cwd;
  final List<SessionMode> modes;
  final String? modeId;
  final List<SessionModel> models;
  final String? modelId;

  /// Claude lists its models as a config option (`configOptions`, id
  /// `model`) instead of `models`: then the model changes through it.
  final String? modelOption;
}

/// A model the agent offers (Opus, Sonnet, GPT…).
class SessionModel {
  const SessionModel(this.id, this.name, [this.description = '']);

  final String id;
  final String name;
  final String description;
}

/// A permission mode offered by the agent (Manual, Auto, Read-only…).
class SessionMode {
  const SessionMode(this.id, this.name, [this.description = '']);

  final String id;
  final String name;
  final String description;
}

/// The agent's permission mode changed (it may refuse the one asked for).
class ModeChanged extends SessionEvent {
  const ModeChanged(this.modeId, {super.at});

  final String modeId;
}

/// The model changed (Mikky asked for another one).
class ModelChanged extends SessionEvent {
  const ModelChanged(this.modelId, {super.at});

  final String modelId;
}

/// The agent (or Mikky) named the session.
class TitleChanged extends SessionEvent {
  const TitleChanged(this.title, {super.at});

  final String title;
}

/// A turn begins: the agent works until [TurnEnded].
class TurnStarted extends SessionEvent {
  const TurnStarted({super.at});
}

/// Why a turn ended.
enum StopReason { endTurn, cancelled, refused, maxTokens, rateLimited, error }

class TurnEnded extends SessionEvent {
  const TurnEnded(this.reason, {this.message, super.at});

  final StopReason reason;

  /// Error text, for [StopReason.error] and [StopReason.rateLimited].
  final String? message;
}

/// The user wrote. [queued]: slipped in while the agent was working.
class UserMessage extends SessionEvent {
  const UserMessage(this.text, {this.queued = false, this.messageId, super.at});

  final String text;
  final bool queued;
  final String? messageId;
}

/// Text from the agent, whole or a chunk of message [messageId].
/// [thought]: its reasoning, not its answer.
class AgentMessage extends SessionEvent {
  const AgentMessage(this.text, {this.messageId, this.thought = false, super.at});

  final String text;
  final String? messageId;
  final bool thought;
}

/// What a tool does, as ACP names it.
enum ToolKind { read, edit, delete, move, search, execute, think, fetch, other }

enum ToolStatus { pending, running, completed, failed }

/// A file change: [oldText] null for a new file.
class FileDiff {
  const FileDiff(this.path, this.oldText, this.newText);

  final String path;
  final String? oldText;
  final String newText;
}

/// A tool call or an update of one. Null fields are unchanged.
class ToolCallEvent extends SessionEvent {
  const ToolCallEvent(
    this.id, {
    this.name,
    this.kind,
    this.title,
    this.status,
    this.command,
    this.path,
    this.diff,
    this.output,
    super.at,
  });

  final String id;

  /// The agent's own tool name (Write, Bash, exec_command…).
  final String? name;
  final ToolKind? kind;
  final String? title;
  final ToolStatus? status;
  final String? command;
  final String? path;
  final FileDiff? diff;
  final String? output;
}

enum PlanStatus { pending, inProgress, completed }

class PlanEntry {
  const PlanEntry(this.content, this.status);

  final String content;
  final PlanStatus status;

  @override
  bool operator ==(Object other) => other is PlanEntry && other.content == content && other.status == status;

  @override
  int get hashCode => Object.hash(content, status);

  @override
  String toString() => '$status $content';
}

/// The agent's task list, whole (the metro line).
class PlanChanged extends SessionEvent {
  const PlanChanged(this.entries, {super.at});

  final List<PlanEntry> entries;
}

/// One answer the agent offers for a permission request.
class PermissionOption {
  const PermissionOption(this.id, this.name, this.kind);

  final String id;
  final String name;

  /// allow_once, allow_always, reject_once or reject_always.
  final String kind;

  bool get allows => kind.startsWith('allow');
}

/// The agent waits for the user's yes or no.
class PermissionAsked extends SessionEvent {
  const PermissionAsked(
    this.requestId, {
    required this.toolCallId,
    required this.title,
    this.command,
    this.options = const [],
    super.at,
  });

  /// JSON-RPC id of the request, to answer it.
  final Object requestId;
  final String? toolCallId;
  final String title;
  final String? command;
  final List<PermissionOption> options;
}

class PermissionAnswered extends SessionEvent {
  const PermissionAnswered(this.requestId, {required this.allowed, super.at});

  final Object requestId;
  final bool allowed;
}

/// One choice of a [Question].
class QuestionChoice {
  const QuestionChoice(this.label, [this.description = '']);

  final String label;
  final String description;
}

/// One question of a [QuestionAsked] form, with its choices.
class Question {
  const Question(this.key, {required this.text, this.title, this.choices = const [], this.multiple = false, this.otherKey});

  /// The form field to answer in.
  final String key;
  final String text;

  /// Short header (« Base de données »…).
  final String? title;
  final List<QuestionChoice> choices;

  /// Several choices at once.
  final bool multiple;

  /// The free-text field that goes with it (« Autre »), if any.
  final String? otherKey;
}

/// The agent asks the user to choose (Claude's question tool, as an ACP
/// form: `elicitation/create`). It waits for the answer.
class QuestionAsked extends SessionEvent {
  const QuestionAsked(this.requestId, {required this.message, required this.questions, super.at});

  final Object requestId;
  final String message;
  final List<Question> questions;
}

class QuestionAnswered extends SessionEvent {
  const QuestionAnswered(this.requestId, {super.at});

  final Object requestId;
}
