import 'package:flutter/widgets.dart';

import '../ui/brand_logo.dart';
import '../ui/cards.dart';
import '../ui/sheet.dart';
import '../ui/sliding_hover.dart';
import '../ui/status.dart';

/// One agent of the history: its tool, its title, when and where it ran.
typedef HistoryRow = ({String id, String title, Brand brand, String when});

/// The history, in the sheet over the home (trial, 2026-10-02): the rows
/// of the old home's history — the tool's logo, the title, when — the
/// white square sliding under the mouse, the grey star (its menu) on the
/// right. A click closes the sheet and opens the agent: it comes back
/// among the apps.
class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.rows, this.onOpen, this.onMenu});

  final List<HistoryRow> rows;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onMenu;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
    child: SlidingHover(
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows)
            AgentCard(
              key: ValueKey(r.id),
              status: UiStatus.finished,
              title: r.title,
              who: r.when,
              brand: r.brand,
              style: AgentCardStyle.old,
              onTap: () {
                Sheet.close(context);
                onOpen?.call(r.id);
              },
              onMenu: onMenu == null ? null : () => onMenu!(r.id),
            ),
        ],
      ),
    ),
  );
}
