import '../agents/agent.dart';
import 'rate_limit.dart';
import 'session_event.dart';
import 'sub_agent.dart';

/// One line of a session's thread, as the Chat view shows it.
sealed class ThreadItem {
  const ThreadItem({this.at});

  final DateTime? at;
}

class UserItem extends ThreadItem {
  const UserItem(this.text, {this.queued = false, this.messageId, super.at});

  final String text;

  /// Slipped in while the agent worked: shown where it came in the task.
  final bool queued;
  final String? messageId;
}

class AgentItem extends ThreadItem {
  const AgentItem(this.text, {this.messageId, this.thought = false, super.at});

  final String text;
  final String? messageId;
  final bool thought;
}

class ToolItem extends ThreadItem {
  const ToolItem(
    this.id, {
    this.name,
    this.kind = ToolKind.other,
    this.title = '',
    this.status = ToolStatus.pending,
    this.command,
    this.path,
    this.diff,
    this.diffs = const [],
    this.output,
    this.agent,
    super.at,
  });

  final String id;
  final String? name;
  final ToolKind kind;
  final String title;
  final ToolStatus status;
  final String? command;
  final String? path;
  final FileDiff? diff;

  /// See [ToolCallEvent.diffs]; empty: [diff] alone.
  final List<FileDiff> diffs;
  final String? output;

  /// See [ToolCallEvent.agent].
  final String? agent;

  /// It launched a sub-agent.
  bool get launchesAgent => agent != null || const {'Agent', 'Task', 'agent'}.contains(name);

  /// Every part of the change it made, in order.
  List<FileDiff> get changes => diffs.isNotEmpty ? diffs : [?diff];

  bool get active => status == ToolStatus.pending || status == ToolStatus.running;

  ToolItem merge(ToolCallEvent e) => ToolItem(
    id,
    name: e.name ?? name,
    kind: e.kind ?? kind,
    title: e.title ?? (title.isEmpty ? (e.command ?? '') : title),
    status: e.status ?? status,
    command: e.command ?? command,
    path: e.path ?? path,
    diff: e.diff ?? diff,
    diffs: e.diff == null ? diffs : (e.diffs ?? const []),
    output: e.output ?? output,
    agent: e.agent ?? agent,
    at: at,
  );
}

/// A turn: from the user's message to the agent's answer. Once ended, the
/// app shows it as a « Tâche terminée » card (UX `ux-a.html`).
class TurnSpan {
  const TurnSpan(this.start, {this.end, this.reason, this.message, this.plan = const [], this.resetsAt});

  final DateTime? resetsAt;

  /// Index of its first item in [SessionLog.items]; [end] is exclusive,
  /// null while the turn runs.
  final int start;
  final int? end;
  final StopReason? reason;
  final String? message;

  /// The agent's task list during this turn (the metro line).
  final List<PlanEntry> plan;

  bool get running => end == null;

  TurnSpan copyWith({int? end, StopReason? reason, String? message, List<PlanEntry>? plan, DateTime? resetsAt}) =>
      TurnSpan(
        start,
        end: end ?? this.end,
        reason: reason ?? this.reason,
        message: message ?? this.message,
        plan: plan ?? this.plan,
        resetsAt: resetsAt ?? this.resetsAt,
      );
}

/// Everything known about one session, folded from its [SessionEvent]s:
/// the thread, the turns, the plan, the pending permission requests, and
/// the state Mikky and the island show.
class SessionLog {
  /// Child sessions attached by the watcher, never separate home entries.
  List<SubAgentLog> subAgents = const [];

  SubAgentLog? subAgentOf(ToolItem tool) => subAgents.where((a) => a.id == tool.agent || a.tool == tool.id).firstOrNull;

  Iterable<SubAgentLog> get descendants {
    final seen = <SessionLog>{this};
    Iterable<SubAgentLog> visit(SessionLog log) sync* {
      for (final child in log.subAgents) {
        if (!seen.add(child.log)) continue;
        yield child;
        yield* visit(child.log);
      }
    }

    return visit(this);
  }

  String? sessionId;
  String? cwd;
  String? title;

  /// The software the session runs in (VS Code, a terminal…), if known.
  AgentApp? app;
  String? modeId;
  List<SessionMode> modes = const [];
  String? modelId;
  List<SessionModel> models = const [];

  /// See [SessionStarted.modelOption].
  String? modelOption;

  /// The model's context: tokens in it, and its size (null: unknown).
  int? contextUsed;
  int? contextSize;

  /// Tokens used by every turn so far.
  int tokens = 0;

  /// The subscription's limits, as last seen.
  LimitsSeen? limits;

  /// The « / » commands the agent offers.
  List<AgentCommand> commands = const [];

  /// Time of the first and of the latest event that had one.
  DateTime? startedAt;
  DateTime? lastEventAt;

  /// Grows by one at each change: a cheap way to know when to redraw.
  int version = 0;

  final List<ThreadItem> _items = [];
  final Map<String, int> _tools = {};
  final List<TurnSpan> _turns = [];
  final Map<Object, PermissionAsked> _pending = {};
  QuestionAsked? _question;
  SessionEvent? _externalRequest;

  /// A live request held by the backend, separate from transcript history.
  /// Replacing its snapshot never creates a turn, tool or duplicate message.
  void setExternalRequest(SessionEvent? request) {
    assert(request == null || request is PermissionAsked || request is QuestionAsked);
    if (identical(_externalRequest, request)) return;
    _externalRequest = request;
    version++;
  }

  DateTime? _lastUserAt;

  /// The actual limit, including a child stopped on this task. A new user
  /// request clears old child limits; automated notifications do not.
  SessionLog? get limitSource => _limitSource({});

  SessionLog? _limitSource(Set<SessionLog> seen) {
    if (!seen.add(this)) return null;
    if (_turns.lastOrNull?.reason == StopReason.rateLimited) return this;
    final blocked =
        subAgents
            .map((a) => a.log._limitSource(seen))
            .nonNulls
            .where(
              (log) =>
                  log.turns.lastOrNull?.reason == StopReason.rateLimited &&
                  (_lastUserAt == null || log.lastEventAt == null || !log.lastEventAt!.isBefore(_lastUserAt!)),
            )
            .toList()
          ..sort((a, b) => (b.lastEventAt ?? DateTime(0)).compareTo(a.lastEventAt ?? DateTime(0)));
    return blocked.firstOrNull;
  }

  String? get limitMessage => limitSource?.turns.last.message;
  DateTime? get limitSeenAt => limitSource?.lastEventAt;

  List<ThreadItem> get items => List.unmodifiable(_items);
  List<TurnSpan> get turns => List.unmodifiable(_turns);

  /// Permission requests waiting for the user, oldest first.
  List<PermissionAsked> get pending => switch (_externalRequest) {
    final PermissionAsked request => [request],
    QuestionAsked() => const [],
    _ => List.unmodifiable(_pending.values),
  };

  /// A question with choices waiting for the user, if any.
  QuestionAsked? get question => switch (_externalRequest) {
    final QuestionAsked request => request,
    PermissionAsked() => null,
    _ => _question,
  };

  /// True while the agent works on a turn.
  bool get working => _turns.isNotEmpty && _turns.last.running;

  /// The latest turn's task list.
  List<PlanEntry> get plan => _turns.isEmpty ? const [] : _turns.last.plan;

  void applyAll(Iterable<SessionEvent> events) => events.forEach(apply);

  void apply(SessionEvent e) {
    version++;
    final at = e.at;
    if (at != null) {
      startedAt ??= at;
      lastEventAt = at;
    }
    switch (e) {
      case SessionStarted():
        sessionId = e.sessionId;
        cwd = e.cwd ?? cwd;
        app = e.app ?? app;
        if (e.modes.isNotEmpty) modes = e.modes;
        modeId = e.modeId ?? modeId;
        if (e.models.isNotEmpty) models = e.models;
        modelId = e.modelId ?? modelId;
        modelOption = e.modelOption ?? modelOption;
      case ModelChanged():
        modelId = e.modelId;
      case ModeChanged():
        modeId = e.modeId;
      case TitleChanged():
        title = e.title;
      case TurnStarted():
        _closeTurn(StopReason.cancelled, null);
        _turns.add(TurnSpan(_items.length));
      case TurnEnded():
        _closeTurn(e.reason, e.message, resetsAt: e.resetsAt);
        _pending.clear();
        _question = null;
      case UserMessage():
        if (!e.queued) _lastUserAt = e.at;
        if (e.messageId?.startsWith('mikky-') != true ||
            !_items.whereType<UserItem>().any((u) => u.messageId == e.messageId)) {
          _items.add(UserItem(e.text, queued: e.queued, messageId: e.messageId, at: at));
        }
      case AgentMessage():
        // A message slipped in while the agent was writing waits after the
        // end of that answer, where the agent actually reads it.
        var i = _items.length - 1;
        while (i >= 0 && _items[i] is UserItem && (_items[i] as UserItem).queued) {
          i--;
        }
        final last = i < 0 ? null : _items[i];
        final continues =
            last is AgentItem && last.thought == e.thought && (e.messageId == null || last.messageId == e.messageId);
        if (continues && (i == _items.length - 1 || e.messageId != null)) {
          _items[i] = AgentItem(last.text + e.text, messageId: last.messageId, thought: last.thought, at: last.at);
        } else {
          _items.add(AgentItem(e.text, messageId: e.messageId, thought: e.thought, at: at));
        }
      case ToolCallEvent():
        final i = _tools[e.id];
        if (i == null) {
          _tools[e.id] = _items.length;
          _items.add(ToolItem(e.id, at: at).merge(e));
        } else {
          _items[i] = (_items[i] as ToolItem).merge(e);
        }
      case PlanChanged():
        if (_turns.isEmpty) _turns.add(TurnSpan(_items.length));
        _turns[_turns.length - 1] = _turns.last.copyWith(plan: e.entries);
      case PermissionAsked():
        _pending[e.requestId] = e;
      case PermissionAnswered():
        _pending.remove(e.requestId);
      case ContextUsed():
        contextUsed = e.used;
        contextSize = e.size;
      case TokensUsed():
        tokens += e.total;
      case LimitsSeen():
        // Codex also reports other counters (« premium ») with no window:
        // they would hide the real ones.
        if (e.short != null || e.long != null) limits = e;
      case CommandsChanged():
        commands = e.commands;
      case QuestionAsked():
        _question = e;
      case QuestionAnswered():
        if (_question?.requestId == e.requestId) _question = null;
    }
  }

  void _closeTurn(StopReason reason, String? message, {DateTime? resetsAt}) {
    if (!working) return;
    // A tool still running when the turn ends was stopped with it; a
    // sub-agent goes on by itself.
    for (var i = _turns.last.start; i < _items.length; i++) {
      final item = _items[i];
      if (item is ToolItem && item.active && item.agent == null) {
        _items[i] = item.merge(ToolCallEvent(item.id, status: ToolStatus.failed));
      }
    }
    _turns[_turns.length - 1] = _turns.last.copyWith(
      end: _items.length,
      reason: reason,
      message: message,
      resetsAt: resetsAt,
    );
  }

  /// State shown by Mikky and the island at [now].
  ///
  /// [staleAfter]: for sessions Mikky only watches, a turn with no news for
  /// that long is taken as dropped (its VS Code window was closed…).
  AgentStatus statusAt(DateTime now, {Duration? staleAfter}) {
    if (question != null) return AgentStatus.question;
    if (pending.isNotEmpty) {
      return _toolFor(pending.first)?.name == 'AskUserQuestion' ? AgentStatus.question : AgentStatus.approval;
    }
    if (limitSource != null) return AgentStatus.rateLimited;
    if (_turns.isEmpty) return AgentStatus.idle;
    final turn = _turns.last;
    if (turn.running) {
      final last = lastEventAt;
      if (staleAfter != null && last != null && now.difference(last) > staleAfter) return AgentStatus.idle;
      return _busy(turn);
    }
    return switch (turn.reason!) {
      StopReason.endTurn || StopReason.refused || StopReason.maxTokens => AgentStatus.finished,
      StopReason.cancelled => AgentStatus.idle,
      StopReason.rateLimited => AgentStatus.rateLimited,
      StopReason.error => AgentStatus.error,
    };
  }

  AgentStatus _busy(TurnSpan turn) {
    for (var i = _items.length - 1; i >= turn.start; i--) {
      final item = _items[i];
      if (item is ToolItem && item.active) {
        return switch (item.kind) {
          ToolKind.read || ToolKind.search || ToolKind.fetch => AgentStatus.searching,
          _ => AgentStatus.working,
        };
      }
      if (item is AgentItem || item is ToolItem) return AgentStatus.thinking;
    }
    return AgentStatus.thinking;
  }

  /// One line for the island and the home card: the command waiting for a
  /// yes, what the agent does now, its answer, or the error.
  String get detail {
    final q = question;
    if (q != null) {
      return _line(q.questions.length == 1 && q.questions.first.text.isNotEmpty ? q.questions.first.text : q.message);
    }
    final asked = pending.firstOrNull;
    if (asked != null) {
      if (identical(asked, _externalRequest)) return _line(asked.command ?? asked.title);
      // The tool's title is the clean command; the request's may be wrapped
      // in a shell (`/usr/bin/zsh -lc "…"` with Codex).
      // The command itself: that is what the user says yes to.
      final tool = _toolFor(asked);
      final command = tool?.command ?? '';
      final title = tool?.title ?? '';
      return _line(command.isNotEmpty ? command : (title.isNotEmpty ? title : asked.command ?? asked.title));
    }
    if (limitSource != null) return limitLine(limitResetsAt, seen: limitSeenAt);
    if (_turns.isEmpty) return '';
    final turn = _turns.last;
    if (!turn.running && turn.reason == StopReason.rateLimited) return limitLine(limitResetsAt, seen: lastEventAt);
    if (!turn.running && turn.message != null) return _line(turn.message!);
    if (turn.reason == StopReason.cancelled) return '';
    for (var i = _items.length - 1; i >= turn.start; i--) {
      final item = _items[i];
      if (item is ToolItem && (turn.running ? item.active : false)) return _line(item.title);
      if (item is AgentItem && !item.thought && item.text.trim().isNotEmpty) {
        return _line(turn.running ? item.text.trim().split('\n').last : item.text.trim().split('\n').first);
      }
      if (item is ToolItem && turn.running) return _line(item.title);
    }
    return '';
  }

  /// The complete action awaiting approval; summaries may shorten [detail],
  /// but the decision card must retain the command the user approves.
  String get requestText {
    final asked = pending.firstOrNull;
    if (asked == null) return detail;
    final tool = _toolFor(asked);
    return [
          asked.command,
          tool?.command,
          tool?.title,
          asked.title,
        ].whereType<String>().where((s) => s.trim().isNotEmpty).firstOrNull ??
        detail;
  }

  ToolItem? _toolFor(PermissionAsked asked) {
    final i = _tools[asked.toolCallId];
    return i == null ? null : _items[i] as ToolItem;
  }

  /// When the subscription limit that stopped the last turn lifts, if the
  /// agent said.
  DateTime? get limitResetsAt {
    final source = limitSource;
    if (source == null) return null;
    final turn = source.turns.last;
    return turn.resetsAt ??
        (turn.message == null ? null : limitResetOf(turn.message!, source.lastEventAt ?? DateTime.now()));
  }

  static String _line(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= 120 ? one : '${one.substring(0, 119)}…';
  }
}
