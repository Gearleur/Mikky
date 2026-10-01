import '../agents/agent.dart';
import 'island_motion.dart';

/// Why the island is open.
enum OpenReason {
  /// Clicked: stays until 60 s without activity.
  click,

  /// Hovered (or peeked from the edge): closes soon after the cursor leaves.
  hover,

  /// An agent needs the user: stays until answered.
  alert,
}

/// What the open island shows.
enum IslandContent { empty, focus, list }

/// Timings of the island rules (spec §5.3), in seconds.
abstract final class IslandTimings {
  static const previewToOpen = .65;
  static const previewLinger = .4;
  static const hoverToOpen = .2;
  static const hoverLeaveToClose = .65;
  static const inactivityClose = 60.0;
  static const countdown = 10.0;
  static const finishedShown = 5.2;
  static const away = 180.0;
  static const dismissedLinger = 2.0;

  /// The split bubble shows alone for this long before the island opens.
  static const bubbleLead = 1.8;
}

/// Everything the app needs to draw the island at one instant.
class IslandSnapshot {
  const IslandSnapshot({
    required this.shape,
    required this.preview,
    required this.openReason,
    required this.content,
    required this.focus,
    required this.agents,
    required this.pendingAlerts,
    required this.bubble,
    required this.closeCountdown,
  });

  final IslandShape shape;

  /// Small pill peeking out while there is no agent (rule 2).
  final bool preview;
  final OpenReason? openReason;
  final IslandContent content;

  /// The agent Mikky stands for (rule 10).
  final Agent? focus;

  /// Agents shown, in order of appearance (finished ones leave after being
  /// shown).
  final List<Agent> agents;

  /// Alerts waiting for an answer, including the one shown.
  final int pendingAlerts;

  /// Split bubble out of the compact island: an alert is waiting.
  final bool bubble;

  /// 1 → 0 during the last 10 s before closing on inactivity, else null.
  final double? closeCountdown;
}

/// The island's rules (spec §5.3, 1 to 10), without Flutter and without
/// timers: feed it events with their clock time, call [advance] at
/// [nextDeadline], read [snapshot].
///
/// The shape is never stored: it is derived from the facts (agents, alert
/// queue, pointer, last activity) and the time, so no combination of events
/// can leave it inconsistent.
class IslandMachine {
  /// [now]: clock time at start; counts as the last user activity.
  IslandMachine({double now = 0, this.layout = IslandLayout.focus})
      : _now = now,
        _lastActivity = now,
        _lastInteraction = now;

  IslandLayout layout;

  List<Agent> _agents = const [];
  final _retired = <String>{};
  final _alerts = <String>[];
  final _escaped = <String>{};
  String? _bubbleHead;
  double? _bubbleSince;
  final _finished = <String>[];
  double? _finishedSince;

  OpenReason? _userOpen;

  /// The user opened the island while there was no agent: it may stay open
  /// empty. Otherwise it closes when the last agent leaves.
  bool _openedEmpty = false;
  double _lastInteraction;
  double? _previewSince;
  bool _pointerIn = false;
  double? _pointerInSince;
  double? _pointerOutSince;
  bool _suppressHover = false;
  double _lastActivity;
  double _now;
  double? _dismissedAt;

  // ---------------------------------------------------------------- inputs

  /// The agent list changed (from an [AgentSource]).
  void setAgents(List<Agent> agents, double now) {
    advance(now);
    final before = {for (final a in _agents) a.id: a};
    for (final a in agents) {
      final was = before[a.id];
      final isNew = was == null || was.status != a.status;
      if (isNew && (a.status.needsYou || a.status == AgentStatus.finished)) _dismissedAt = null;
      if (a.status.needsYou && isNew && !_alerts.contains(a.id)) {
        _alerts.add(a.id);
      }
      if (a.status.needsYou && isNew) _escaped.remove(a.id);
      if (a.status == AgentStatus.finished && isNew && !_finished.contains(a.id)) {
        _finished.add(a.id);
      }
      if (a.status != AgentStatus.finished) _retired.remove(a.id);
    }
    final byId = {for (final a in agents) a.id: a};
    _alerts.removeWhere((id) => byId[id]?.status.needsYou != true);
    _escaped.removeWhere((id) => !_alerts.contains(id));
    final finishedHead = _finished.isEmpty ? null : _finished.first;
    _finished.removeWhere((id) => byId[id]?.status != AgentStatus.finished);
    if (_finished.isEmpty || _finished.first != finishedHead) _finishedSince = null;
    _retired.removeWhere((id) => !byId.containsKey(id));
    _agents = List.unmodifiable(agents);
    _refresh(now);
  }

  /// The cursor moved. [overIsland]: on the island's shape; [atEdge]: in the
  /// hot zone against the screen edge.
  void pointer(double now, {required bool overIsland, required bool atEdge}) {
    advance(now);
    _lastActivity = now;
    final inside = overIsland || atEdge;
    if (inside != _pointerIn) {
      _pointerIn = inside;
      if (inside) {
        if (!_suppressHover && overIsland) _dismissedAt = null;
        _pointerInSince = now;
        _pointerOutSince = null;
      } else {
        _pointerOutSince = now;
        _pointerInSince = null;
        _suppressHover = false;
      }
    }
    if (inside && _userOpen != null) _lastInteraction = now;
    if (atEdge && !_suppressHover && _previewSince == null && _shapeAt(now) == IslandShape.hidden) {
      _previewSince = now;
    }
    _refresh(now);
  }

  /// Click on the closed island: open now (rule 4). On the open island it
  /// only counts as activity.
  void click(double now) {
    advance(now);
    _dismissedAt = null;
    _lastActivity = now;
    _lastInteraction = now;
    if (_shapeAt(now) != IslandShape.open) {
      _openByUser(OpenReason.click);
      _previewSince = null;
    } else if (_userOpen == OpenReason.hover) {
      _userOpen = OpenReason.click;
    }
  }

  /// Explicit dismissal: compact briefly, then hidden unless an alert still
  /// needs attention. A new alert can open the island again.
  void close(double now) {
    advance(now);
    _lastActivity = now;
    _escaped.addAll(_alerts);
    while (_finished.isNotEmpty) {
      _retireFinished();
    }
    _dismissedAt = now;
    _userOpen = null;
    _previewSince = null;
    _suppressHover = _pointerIn;
    _refresh(now);
  }

  // ------------------------------------------------------------------ time

  /// Applies the rules whose delay is over at [now].
  void advance(double now) {
    _now = now;
    final preview = _previewSince;
    if (preview != null) {
      final inSince = _pointerInSince;
      final outSince = _pointerOutSince;
      if (_pointerIn && inSince != null && now - _max(preview, inSince) >= IslandTimings.previewToOpen) {
        _openByUser(OpenReason.hover);
        _lastInteraction = now;
        _previewSince = null;
      } else if (!_pointerIn && outSince != null && now - outSince >= IslandTimings.previewLinger) {
        _previewSince = null;
      }
    }
    final inSince = _pointerInSince;
    if (_userOpen == null &&
        _previewSince == null &&
        _pointerIn &&
        !_suppressHover &&
        inSince != null &&
        now - inSince >= IslandTimings.hoverToOpen &&
        _shapeAt(now) == IslandShape.compact) {
      _openByUser(OpenReason.hover);
      _lastInteraction = now;
    }
    final outSince = _pointerOutSince;
    if (_userOpen == OpenReason.hover && !_pointerIn && outSince != null && now - outSince >= IslandTimings.hoverLeaveToClose) {
      _userOpen = null;
    }
    if (_userOpen == OpenReason.click && now - _lastInteraction >= IslandTimings.inactivityClose) {
      _userOpen = null;
    }
    final finishedSince = _finishedSince;
    if (finishedSince != null && now - finishedSince >= IslandTimings.finishedShown) {
      _retireFinished();
    }
    _refresh(now);
  }

  /// Next clock time at which [advance] may change something, or null.
  double? get nextDeadline {
    final now = _now;
    final candidates = <double?>[
      if (_previewSince != null && _pointerIn && _pointerInSince != null)
        _max(_previewSince!, _pointerInSince!) + IslandTimings.previewToOpen,
      if (_previewSince != null && !_pointerIn && _pointerOutSince != null)
        _pointerOutSince! + IslandTimings.previewLinger,
      if (_userOpen == null && _previewSince == null && _pointerIn && !_suppressHover && _pointerInSince != null)
        _pointerInSince! + IslandTimings.hoverToOpen,
      if (_userOpen == OpenReason.hover && !_pointerIn && _pointerOutSince != null)
        _pointerOutSince! + IslandTimings.hoverLeaveToClose,
      if (_userOpen == OpenReason.click) _lastInteraction + IslandTimings.inactivityClose,
      if (_bubbleSince != null) _bubbleSince! + IslandTimings.bubbleLead,
      if (_finishedSince != null) _finishedSince! + IslandTimings.finishedShown,
      if (_dismissedAt != null) _dismissedAt! + IslandTimings.dismissedLinger,
      if (_visible.isNotEmpty || _userOpen != null) _lastActivity + IslandTimings.away,
    ];
    double? next;
    for (final c in candidates) {
      if (c != null && c > now && (next == null || c < next)) next = c;
    }
    return next;
  }

  // --------------------------------------------------------------- derived

  List<Agent> get _visible => [
        for (final a in _agents)
          if (!_retired.contains(a.id)) a,
      ];

  /// The alert shown (rule 9: first come, first served), unless closed.
  String? get _alertHead {
    for (final id in _alerts) {
      if (!_escaped.contains(id)) return id;
    }
    return null;
  }

  Agent? _agent(String? id) {
    if (id == null) return null;
    for (final a in _agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  bool _isAway(double now) => now - _lastActivity >= IslandTimings.away;

  /// Updates the bookkeeping that depends on the facts: which alert shows
  /// in the bubble, when the next finished agent starts being shown.
  void _refresh(double now) {
    final head = _alertHead;
    if (head != _bubbleHead) {
      // Open for another reason, or on the previous alert (not the new head).
      final wasOpen = _userOpen != null || (_bubbleHead != null && _bubbleSince == null);
      _bubbleHead = head;
      // Already open: switch at once. Closed: the bubble comes out first.
      _bubbleSince = head == null || wasOpen ? null : now;
    }
    final since = _bubbleSince;
    if (since != null && now - since >= IslandTimings.bubbleLead) _bubbleSince = null;
    if (_finishedSince == null && _finished.isNotEmpty && head == null) _finishedSince = now;
    if (_userOpen != null) {
      final empty = _visible.isEmpty;
      if (!empty) {
        _openedEmpty = false;
      } else if (!_openedEmpty) {
        // Opened for agents that are all gone now.
        _userOpen = null;
      }
    }
  }

  /// Opens at the user's request (click, hover, peek).
  void _openByUser(OpenReason reason) {
    _dismissedAt = null;
    if (_userOpen == null) _openedEmpty = _visible.isEmpty;
    _userOpen = reason;
  }

  void _retireFinished() {
    if (_finished.isNotEmpty) _retired.add(_finished.removeAt(0));
    _finishedSince = null;
  }

  OpenReason? _openReasonAt(double now) {
    // While the bubble comes out alone, a click opens at once.
    if (_alertHead != null) return _bubbleSince != null && _userOpen == null ? null : OpenReason.alert;
    return _userOpen;
  }

  IslandShape _shapeAt(double now) {
    final dismissed = _dismissedAt;
    if (dismissed != null && _userOpen == null && _previewSince == null) {
      if (_alerts.isNotEmpty) return IslandShape.compact;
      return now < dismissed + IslandTimings.dismissedLinger ? IslandShape.compact : IslandShape.hidden;
    }
    if (_openReasonAt(now) != null) return IslandShape.open;
    if (_alertHead != null) return IslandShape.compact; // bubble first
    // Just finished: the compact island, its state under Mikky (user
    // request, 2026-10-01: not the big island).
    if (_finishedSince != null) return IslandShape.compact;
    if (!_isAway(now) && _visible.isNotEmpty) return IslandShape.compact;
    if (_previewSince != null) return IslandShape.compact;
    return IslandShape.hidden;
  }

  IslandSnapshot get snapshot {
    final now = _now;
    final shape = _shapeAt(now);
    final reason = _openReasonAt(now);
    final visible = _visible;
    final Agent? focus = switch (reason) {
      OpenReason.alert => _agent(_alertHead),
      null when _finishedSince != null => _agent(_finished.firstOrNull),
      _ => _priorityFocus(visible),
    };
    final content = switch (reason) {
      null => IslandContent.focus,
      OpenReason.alert => IslandContent.focus,
      _ when visible.isEmpty => IslandContent.empty,
      _ => layout == IslandLayout.list ? IslandContent.list : IslandContent.focus,
    };
    double? countdown;
    if (shape == IslandShape.open && reason == OpenReason.click) {
      final left = IslandTimings.inactivityClose - (now - _lastInteraction);
      if (left <= IslandTimings.countdown) countdown = (left / IslandTimings.countdown).clamp(0.0, 1.0);
    }
    return IslandSnapshot(
      shape: shape,
      preview: shape == IslandShape.compact && visible.isEmpty && _alerts.isEmpty,
      openReason: shape == IslandShape.open ? reason : null,
      content: content,
      focus: focus,
      agents: visible,
      pendingAlerts: _alerts.length,
      // What needs the user always comes out in the bubble, never under Mikky.
      bubble: shape == IslandShape.compact && (_alerts.isNotEmpty || (focus?.status.needsYou ?? false)),
      closeCountdown: countdown,
    );
  }
}

Agent? _priorityFocus(List<Agent> agents) {
  int rank(AgentStatus status) => switch (status) {
    AgentStatus.approval || AgentStatus.question || AgentStatus.error => 4,
    AgentStatus.rateLimited => 3,
    AgentStatus.working || AgentStatus.thinking || AgentStatus.searching => 2,
    AgentStatus.finished => 1,
    AgentStatus.paused || AgentStatus.idle => 0,
  };
  Agent? best;
  for (final agent in agents) {
    if (best == null || rank(agent.status) > rank(best.status) ||
        (rank(agent.status) == rank(best.status) && agent.statusSince > best.statusSince)) {
      best = agent;
    }
  }
  return best;
}

double _max(double a, double b) => a > b ? a : b;
