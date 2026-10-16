import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/enchant.dart';
import '../home/history_sheet.dart';
import '../home/home_app.dart';
import '../home/home_layout.dart';
import '../home/home_view.dart';
import '../home/notch_request.dart';
import '../home/task_glance.dart';
import '../ui/brand/brand_logo.dart';
import '../ui/foundation/status.dart';
import 'session_text.dart';

/// More finished agents than this go to the history.
const maxDone = 5;

/// The home's apps from the agents Mikky knows (2026-10-02): one app per
/// agent for now, in the order of the old home — waiting, at work, then
/// finished (the five most recent of the day); pinned first in each, then
/// the most recent. Not the history nor the archives: they have a place
/// of their own (user, 2026-10-02). [recalled]: agents opened from the
/// history, back among the finished ones, first. Paused agents get no
/// state on their tile.
/// [except]: the agent the notch shows beside Mikky: not among the apps
/// too (user, 2026-10-05: « ça fait redondant »).
List<HomeApp> homeApps(
  List<AgentEntry> entries,
  DateTime now, {
  Set<String> recalled = const {},
  String? except,
  Set<String> autoRelaunch = const {},
}) => [
  for (final e in _shown(entries, now, recalled))
    if (e.id != except)
      HomeApp(
        id: e.id,
        name: e.name,
        brand: Brand.of(e.provider),
        status: e.status == AgentStatus.rateLimited && autoRelaunch.contains(e.id)
            ? null
            : appStatus(e.status, e.homeStatus),
        line: appLine(e.homeStatus, e.log, e.lastActivity, now),
        app: e.app,
      ),
];

/// What an app does now, or how it ended, in a few words: the line under
/// its title in the notch (user, 2026-10-05: « un petit texte qui
/// change »).
String appLine(AgentStatus status, SessionLog log, DateTime last, DateTime now) => switch (status) {
  AgentStatus.approval => log.detail.isEmpty ? 'Attend ton feu vert' : 'Attend : ${log.detail}',
  AgentStatus.question => 'Te pose une question',
  AgentStatus.working ||
  AgentStatus.thinking ||
  AgentStatus.searching => log.detail.isEmpty ? 'Au travail' : log.detail,
  AgentStatus.rateLimited => log.detail,
  AgentStatus.error => 'En erreur',
  AgentStatus.paused => 'En pause',
  AgentStatus.finished || AgentStatus.idle => 'Terminée · ${ago(last, now)}',
};

/// A task that ended this long ago is still the one Mikky looks at.
const watchedAfterEnd = Duration(minutes: 10);

/// The task Mikky looks at in the notch (user, 2026-10-05: « la dernière
/// tâche qui est en train d'être faite »): the latest at work or waiting
/// for the user; else the latest that ended in the last
/// [watchedAfterEnd]; else none.
T? watchedOf<T>(
  Iterable<T> items, {
  required AgentStatus Function(T) status,
  required DateTime Function(T) lastActivity,
  required DateTime now,
}) {
  T? latest(bool Function(AgentStatus) keep) {
    T? best;
    for (final i in items) {
      if (keep(status(i)) && (best == null || lastActivity(i).isAfter(lastActivity(best)))) best = i;
    }
    return best;
  }

  final active = latest(
    (s) => switch (s) {
      AgentStatus.working ||
      AgentStatus.thinking ||
      AgentStatus.searching ||
      AgentStatus.approval ||
      AgentStatus.question => true,
      _ => false,
    },
  );
  if (active != null) return active;
  final ended = latest((s) => s == AgentStatus.finished || s == AgentStatus.rateLimited || s == AgentStatus.error);
  return ended != null && now.difference(lastActivity(ended)) <= watchedAfterEnd ? ended : null;
}

/// [watchedOf] on the agents: not archived ones, nor paused ones.
WatchedTask? watchedTask(List<AgentEntry> entries, DateTime now) {
  final e = watchedOf(
    entries.where((e) => !e.mark.archived),
    status: (e) => e.homeStatus,
    lastActivity: (e) => e.lastActivity,
    now: now,
  );
  return e == null ? null : WatchedTask(id: e.id, name: e.name, log: e.log, status: e.homeStatus, app: e.app);
}

/// An app's state on its tile, from its agent's [status] and the one the
/// home sorts it by ([home]). Paused by the user: nothing. An agent whose
/// turn is over (idle, waiting for a new message) has finished: green
/// (2026-10-02: « le vert n'apparaît pas »), as a limit or an error the
/// user settled.
UiStatus? appStatus(AgentStatus status, AgentStatus home) {
  if (status == AgentStatus.paused) return null;
  return switch (UiStatus.of(home)) {
    UiStatus.paused => UiStatus.finished,
    final s => s,
  };
}

/// The history (2026-10-02): every agent the home does not show, but the
/// archives — the most recent first, with when and where it last ran.
List<HistoryRow> historyRows(List<AgentEntry> entries, DateTime now, {Set<String> recalled = const {}}) {
  final shown = {for (final e in _shown(entries, now, recalled)) e.id};
  final rest = [
    for (final e in entries)
      if (!e.mark.archived && !shown.contains(e.id)) e,
  ]..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  return [
    for (final e in rest)
      (
        id: e.id,
        title: e.name,
        brand: Brand.of(e.provider),
        when: '${ago(e.lastActivity, now)}${e.host == AgentHost.wsl ? ' · WSL' : ''}',
      ),
  ];
}

List<AgentEntry> _shown(List<AgentEntry> entries, DateTime now, Set<String> recalled) {
  final groups = groupHome(
    [
      for (final e in entries)
        if (!e.mark.archived || recalled.contains(e.id)) e,
    ],
    status: (e) => e.homeStatus,
    lastActivity: (e) => e.lastActivity,
    now: now,
  );
  List<AgentEntry> ordered(Iterable<AgentEntry> g) => [
    ...g.where((e) => e.mark.pinned),
    ...g.where((e) => !e.mark.pinned),
  ];
  final done = [...groups[HomeGroup.done]!, ...groups[HomeGroup.history]!];
  return [
    ...ordered(groups[HomeGroup.waiting]!),
    ...ordered(groups[HomeGroup.working]!),
    ...done.where((e) => recalled.contains(e.id)),
    ...ordered(groups[HomeGroup.done]!.where((e) => !recalled.contains(e.id))).take(maxDone),
  ];
}

/// The home on the real agents, at the top or at the right. A tile opens
/// its agent's page; « + » and the tools' rail, the Chat ([chat], a new
/// agent); the history button, the history over it. Mikky is the
/// island's own, drawn over his place.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.entries,
    required this.open,
    this.canLaunch = true,
    this.layout = HomeLayout.right,
    this.recalled = const {},
    this.recall,
    this.onMenu,
    this.canAnswer,
    this.canAnswerQuestion,
    this.answer,
    this.answerQuestion,
    this.reveal,
    this.onQuestionChanged,
  });

  final List<AgentEntry> entries;

  /// An agent's id.
  final ValueChanged<String> open;
  final bool canLaunch;
  final HomeLayout layout;

  /// Agents opened from the history (see [homeApps]).
  final Set<String> recalled;

  /// A row of the history: its agent's page, and back among the apps.
  /// Null: [open].
  final ValueChanged<String>? recall;

  /// An agent's menu: right click on its app/task, or ⋯ in the history.
  final ValueChanged<String>? onMenu;
  final bool Function(String)? canAnswer, canAnswerQuestion;
  final void Function(String, AgentAnswer)? answer;
  final void Function(String, Map<String, Object>?)? answerQuestion;
  final ValueChanged<String>? reveal;

  /// Keep the island's size in sync with the request currently shown.
  final ValueChanged<bool>? onQuestionChanged;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _deferred = <(String, Object)>{};
  String? _selected;
  bool? _question;

  static Object? _requestId(AgentEntry e) => e.log.question?.requestId ?? e.log.pending.firstOrNull?.requestId;

  /// Only a waiting tile changes the home. Other tiles still open their
  /// agent as before. Reopening a deferred request does not answer it.
  void showRequest(String id) {
    if (!widget.layout.isTop) return;
    final entry = widget.entries.where((e) => e.id == id).firstOrNull;
    final request = entry == null ? null : _requestId(entry);
    if (request == null) return;
    setState(() {
      _deferred.remove((id, request));
      _selected = id;
    });
  }

  AgentEntry? _request() {
    if (!widget.layout.isTop) return null;
    final waiting =
        widget.entries
            .where(
              (e) =>
                  !e.mark.archived &&
                  (e.status == AgentStatus.approval || e.status == AgentStatus.question) &&
                  _requestId(e) != null,
            )
            .toList()
          ..sort((a, b) => a.lastActivity.compareTo(b.lastActivity));
    _deferred.removeWhere((key) => !waiting.any((e) => (e.id, _requestId(e)) == key));
    final available = waiting.where((e) => !_deferred.contains((e.id, _requestId(e))));
    return available.where((e) => e.id == _selected).firstOrNull ?? available.firstOrNull;
  }

  NotchRequest _requestView(AgentEntry entry) {
    final id = entry.id, request = _requestId(entry)!;
    // A replacement request must never receive a click meant for the old
    // one during the service's short rendering debounce.
    bool current() {
      final latest = widget.entries.where((e) => e.id == id).firstOrNull;
      return latest != null &&
          !latest.mark.archived &&
          _requestId(latest) == request &&
          (latest.status == AgentStatus.approval || latest.status == AgentStatus.question);
    }

    return NotchRequest(
      key: ValueKey((id, request)),
      name: entry.name,
      log: entry.log,
      onLater: () => setState(() {
        _deferred.add((id, request));
        _selected = null;
      }),
      onOpen: () => widget.open(id),
      onReveal: widget.reveal == null ? null : () => widget.reveal!(id),
      onAnswer: widget.answer != null && (widget.canAnswer?.call(id) ?? false)
          ? (answer) {
              if (current()) widget.answer!(id, answer);
            }
          : null,
      onAnswerQuestion: widget.answerQuestion != null && (widget.canAnswerQuestion?.call(id) ?? false)
          ? (answers) {
              if (current()) widget.answerQuestion!(id, answers);
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Enchantments.instance, builder: (context, _) => _view(context));

  Widget _view(BuildContext context) {
    final entries = widget.entries, layout = widget.layout;
    final recalled = widget.recalled, onMenu = widget.onMenu;
    final now = DateTime.now();
    // The notch, at the top and (since 2026-10-08) at the right.
    final autoRelaunch = {
      for (final e in entries)
        if (Enchantments.instance.isOn(e.id)) e.id,
    };
    final attention = Enchantments.instance.attentionEntries(entries);
    final request = _request();
    final question = layout.isTop && request?.log.question != null;
    if (_question != question) {
      _question = question;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _question == question) widget.onQuestionChanged?.call(question);
      });
    }
    final watched = request != null
        ? WatchedTask(id: request.id, name: request.name, log: request.log, status: request.status, app: request.app)
        : layout.notch
        ? watchedTask(attention.where((e) => !_deferred.contains((e.id, _requestId(e)))).toList(), now)
        : null;
    return HomeView(
      key: ValueKey(layout.placement),
      layout: layout,
      watched: watched,
      request: request == null ? null : _requestView(request),
      apps: homeApps(entries, now, recalled: recalled, except: watched?.id, autoRelaunch: autoRelaunch),
      drawMikky: false,
      onOpen: (app) {
        final entry = entries.where((e) => e.id == app.id).firstOrNull;
        if (layout.isTop &&
            entry != null &&
            _requestId(entry) != null &&
            (entry.status == AgentStatus.approval || entry.status == AgentStatus.question)) {
          showRequest(app.id);
        } else {
          widget.open(app.id);
        }
      },
      onMenu: onMenu,
      // « + », the tools and the Chat mode: the new chat's page.
      onNew: widget.canLaunch ? () => widget.open('new') : null,
      onHistory: (within) => showHistory(
        within,
        rows: historyRows(entries, DateTime.now(), recalled: recalled),
        onOpen: widget.recall ?? widget.open,
        onMenu: onMenu,
      ),
    );
  }
}
