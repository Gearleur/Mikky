import 'package:flutter/widgets.dart';

import '../ui/brand_logo.dart';
import '../ui/cards.dart';
import '../ui/field.dart';
import '../ui/sheet.dart';
import '../ui/sliding_hover.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';

/// One agent of the history: its tool, its title, when and where it ran.
typedef HistoryRow = ({String id, String title, Brand brand, String when});

/// The history, as a sheet over the home's window [within] (2026-10-02):
/// centered, « Historique » and the count, a search field, then the rows.
/// A row closes it and opens its agent ([onOpen]); it comes back among the
/// apps.
Future<void> showHistory(BuildContext within, {required List<HistoryRow> rows, ValueChanged<String>? onOpen, ValueChanged<String>? onMenu}) =>
    showSheet(within, title: 'Historique', caption: '${rows.length}', builder: (_) => HistoryBody(rows: rows, onOpen: onOpen, onMenu: onMenu));

/// What the history sheet holds: a small search field, then the list. The
/// search only looks in the titles shown for now (2026-10-02: « pas
/// fonctionnelle pour le moment, mais penses-y »); later it asks `mikkyd`
/// (titles, folders, what was said).
class HistoryBody extends StatefulWidget {
  const HistoryBody({super.key, required this.rows, this.onOpen, this.onMenu});

  final List<HistoryRow> rows;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onMenu;

  @override
  State<HistoryBody> createState() => _HistoryBodyState();
}

class _HistoryBodyState extends State<HistoryBody> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final q = _search.text.trim().toLowerCase();
    final rows = q.isEmpty ? widget.rows : [for (final r in widget.rows) if (r.title.toLowerCase().contains(q)) r];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: SearchField(small: true, icon: 'search', placeholder: 'Chercher dans l’historique', controller: _search),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text('Rien trouvé', style: uiText(TextSize.small, color: ui.text3)))
              : HistoryList(rows: rows, onOpen: widget.onOpen, onMenu: widget.onMenu),
        ),
      ],
    );
  }
}

/// The history's rows — the old home's: the tool's logo, the title, when
/// — the white square sliding under the mouse, the grey star (its menu)
/// on the right. A click closes the sheet and opens the agent.
class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.rows, this.onOpen, this.onMenu});

  final List<HistoryRow> rows;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onMenu;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
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
