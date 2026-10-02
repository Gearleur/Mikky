import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../home/home_view.dart';
import '../ui/brand_logo.dart';
import '../ui/status.dart';

/// The home's apps from the agents Mikky knows (2026-10-02): one app per
/// agent for now, in the order of the old home — waiting, at work,
/// finished, then the history; pinned first in each, then the most
/// recent. Archived ones are left out. Paused and old agents get no
/// state on their tile.
List<HomeApp> homeApps(List<AgentEntry> entries, DateTime now) {
  final groups = groupHome(
    [
      for (final e in entries)
        if (!e.mark.archived) e,
    ],
    status: (e) => e.homeStatus,
    lastActivity: (e) => e.lastActivity,
    now: now,
  );
  return [
    for (final g in HomeGroup.values)
      for (final e in [...groups[g]!.where((e) => e.mark.pinned), ...groups[g]!.where((e) => !e.mark.pinned)])
        HomeApp(
          id: e.id,
          name: e.name,
          brand: Brand.of(e.provider),
          status: g == HomeGroup.history || e.status == AgentStatus.paused ? null : UiStatus.of(e.status),
        ),
  ];
}

/// The home of the window at the right: the new home on the real agents.
/// A tile opens its agent's page; the tools' rail, a new agent. Mikky is
/// the island's own, drawn over his place.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.entries, required this.open, this.canLaunch = true, this.layout = HomeLayout.right});

  final List<AgentEntry> entries;

  /// An agent's id, or `new`.
  final ValueChanged<String> open;
  final bool canLaunch;
  final HomeLayout layout;

  @override
  Widget build(BuildContext context) => HomeView(
    layout: layout,
    apps: homeApps(entries, DateTime.now()),
    drawMikky: false,
    onOpen: (app) => open(app.id),
    onTools: canLaunch ? () => open('new') : null,
  );
}
