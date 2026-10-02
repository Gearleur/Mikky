import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../home/history_sheet.dart';
import '../home/home_view.dart';
import '../ui/brand_logo.dart';
import '../ui/status.dart';
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
List<HomeApp> homeApps(List<AgentEntry> entries, DateTime now, {Set<String> recalled = const {}}) => [
  for (final e in _shown(entries, now, recalled))
    HomeApp(
      id: e.id,
      name: e.name,
      brand: Brand.of(e.provider),
      status: e.status == AgentStatus.paused ? null : UiStatus.of(e.homeStatus),
    ),
];

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
/// its agent's page; « + » and the tools' rail, the Chat ([chat], the
/// new agent); the history button, the history over it. Mikky is the
/// island's own, drawn over his place.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.entries,
    required this.open,
    this.canLaunch = true,
    this.layout = HomeLayout.right,
    this.recalled = const {},
    this.recall,
    this.chat,
    this.onMenu,
  });

  final List<AgentEntry> entries;

  /// An agent's id, or `new`.
  final ValueChanged<String> open;
  final bool canLaunch;
  final HomeLayout layout;

  /// Agents opened from the history (see [homeApps]).
  final Set<String> recalled;

  /// A row of the history: its agent's page, and back among the apps.
  /// Null: [open].
  final ValueChanged<String>? recall;

  /// The home's Chat; null: « + » opens the new agent's page.
  final Widget Function(VoidCallback toApps)? chat;

  /// An agent's ··· menu (a row of the history).
  final ValueChanged<String>? onMenu;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return HomeView(
      key: ValueKey(layout.placement),
      layout: layout,
      apps: homeApps(entries, now, recalled: recalled),
      drawMikky: false,
      onOpen: (app) => open(app.id),
      onNew: canLaunch ? () => open('new') : null,
      chat: canLaunch ? chat : null,
      onHistory: (within) => showHistory(within, rows: historyRows(entries, DateTime.now(), recalled: recalled), onOpen: recall ?? open, onMenu: onMenu),
    );
  }
}
