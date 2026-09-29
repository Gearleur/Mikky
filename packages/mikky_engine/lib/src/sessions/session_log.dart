import '../agents/agent.dart';
import 'session_event.dart';

/// One line of a session's thread, as the Chat view shows it.
sealed class ThreadItem {
  const ThreadItem({this.at});

  final DateTime? at;
}

class UserItem extends ThreadItem {
  const UserItem(this.text, {this.queued = false, super.at});

  final String text;

  /// Slipped in while the agent worked: shown between the tasks in Suivi.
  final bool queued;
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
    this.output,
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
  final String? output;

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
        output: e.output ?? output,
        at: at,
      );
}

/// A turn: from the user's message to the agent's answer. Once ended, the
/// app shows it as a « Tâche terminée » card (UX `ux-a.html`).
class TurnSpan {
  const TurnSpan(this.start, {this.end, this.reason, this.message, this.plan = const []});

  /// Index of its first item in [SessionLog.items]; [end] is exclusive,
  /// null while the turn runs.
  final int start;
  final int? end;
  final StopReason? reason;
  final String? message;

  /// The agent's task list during this turn (the metro line).
  final List<PlanEntry> plan;

  bool get running => end == null;

  TurnSpan copyWith({int? end, StopReason? reason, String? message, List<PlanEntry>? plan}) => TurnSpan(
        start,
        end: end ?? this.end,
        reason: reason ?? this.reason,
        message: message ?? this.message,
        plan: plan ?? this.plan,
      );
}

/// Everything known about one session, folded from its [SessionEvent]s:
/// the thread, the turns, the plan, the pending permission requests, and
/// the state Mikky and the island show (MVP spec §6).
class SessionLog {
  String? sessionId;
  String? cwd;
  String? title;
  String? modeId;
  List<SessionMode> modes = const [];
  String? modelId;
  List<SessionModel> models = const [];

  /// See [SessionStarted.modelOption].
  String? modelOption;

  /// Time of the first and of the latest event that had one.
  DateTime? startedAt;
  DateTime? lastEventAt;

  /// Grows by one at each change: a cheap way to know when to redraw.
  int version = 0;

  final List<ThreadItem> _items = [];
  final Map<String, int> _tools = {};
  final List<TurnSpan> _turns = [];
  final Map<Object, PermissionAsked> _pending = {};

  List<ThreadItem> get items => List.unmodifiable(_items);
  List<TurnSpan> get turns => List.unmodifiable(_turns);

  /// Permission requests waiting for the user, oldest first.
  List<PermissionAsked> get pending => List.unmodifiable(_pending.values);

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
        _closeTurn(e.reason, e.message);
        _pending.clear();
      case UserMessage():
        _items.add(UserItem(e.text, queued: e.queued, at: at));
      case AgentMessage():
        // A message slipped in while the agent was writing waits after the
        // end of that answer, where the agent actually reads it.
        var i = _items.length - 1;
        while (i >= 0 && _items[i] is UserItem && (_items[i] as UserItem).queued) {
          i--;
        }
        final last = i < 0 ? null : _items[i];
        final continues = last is AgentItem && last.thought == e.thought && (e.messageId == null || last.messageId == e.messageId);
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
    }
  }

  void _closeTurn(StopReason reason, String? message) {
    if (!working) return;
    // A tool still running when the turn ends was stopped with it.
    for (var i = _turns.last.start; i < _items.length; i++) {
      final item = _items[i];
      if (item is ToolItem && item.active) _items[i] = item.merge(ToolCallEvent(item.id, status: ToolStatus.failed));
    }
    _turns[_turns.length - 1] = _turns.last.copyWith(end: _items.length, reason: reason, message: message);
  }

  /// State shown by Mikky and the island at [now].
  ///
  /// [staleAfter]: for sessions Mikky only watches, a turn with no news for
  /// that long is taken as dropped (its VS Code window was closed…).
  AgentStatus statusAt(DateTime now, {Duration? staleAfter}) {
    if (_pending.isNotEmpty) {
      return _toolFor(_pending.values.first)?.name == 'AskUserQuestion' ? AgentStatus.question : AgentStatus.approval;
    }
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
    final asked = _pending.isEmpty ? null : _pending.values.first;
    if (asked != null) {
      // The tool's title is the clean command; the request's may be wrapped
      // in a shell (`/usr/bin/zsh -lc "…"` with Codex).
      // The command itself: that is what the user says yes to.
      final tool = _toolFor(asked);
      final command = tool?.command ?? '';
      final title = tool?.title ?? '';
      return _line(command.isNotEmpty ? command : (title.isNotEmpty ? title : asked.command ?? asked.title));
    }
    if (_turns.isEmpty) return '';
    final turn = _turns.last;
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

  ToolItem? _toolFor(PermissionAsked asked) {
    final i = _tools[asked.toolCallId];
    return i == null ? null : _items[i] as ToolItem;
  }

  static String _line(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= 120 ? one : '${one.substring(0, 119)}…';
  }
}
