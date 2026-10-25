import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../brand/brand_logo.dart';
import '../controls/buttons.dart';
import '../controls/field.dart';
import '../controls/sliding_hover.dart';
import '../foundation/icons.dart';
import '../foundation/motion.dart';
import '../foundation/surface.dart';
import '../foundation/tokens.dart';
import 'history_activity.dart';
import 'history_motion.dart';
import 'history_row.dart';
import 'history_scroll.dart';

enum HistorySearchMode { centered, dedicated }

/// One- or two-column history with centered search or a dedicated search
/// page reached from a fixed leading navigation rail. Shared by the app
/// and the design boards; dedicated search and one column are the default.
class HistoryView extends StatefulWidget {
  const HistoryView({
    super.key,
    required this.rows,
    this.onClose,
    this.onOpen,
    this.onMenu,
    this.searchMode = HistorySearchMode.dedicated,
    this.initiallySearching = false,
    this.columns = 1,
  }) : assert(columns == 1 || columns == 2);

  // The island's 30 px corners inset by 12 px: matching corner centers
  // keep the lower edge of this panel parallel to the window's edge.
  static const inset = 12.0;
  static const radius = Radii.xl;
  static const rowHeight = 40.0;

  final List<HistoryRow> rows;
  final VoidCallback? onClose;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onMenu;
  final HistorySearchMode searchMode;
  final bool initiallySearching;
  final int columns;

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final _search = TextEditingController();
  late bool _searching = widget.searchMode == HistorySearchMode.dedicated && widget.initiallySearching;

  bool get _dedicated => widget.searchMode == HistorySearchMode.dedicated;

  void _back() {
    if (_dedicated && _searching) {
      _search.clear();
      setState(() => _searching = false);
    } else {
      widget.onClose?.call();
    }
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final query = _search.text.trim().toLowerCase();
    final rows = [
      for (final row in widget.rows)
        if (query.isEmpty || row.title.toLowerCase().contains(query)) row,
    ];
    final content = _dedicated ? _fullHeight(ui, rows, query) : _centered(ui, rows, query);
    return Focus(
      onKeyEvent: (_, event) {
        if (_dedicated && _searching && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _back();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: content,
    );
  }

  Widget _centered(MikkyUi ui, List<HistoryRow> rows, String query) => Padding(
    padding: const EdgeInsets.fromLTRB(HistoryView.inset, 8, HistoryView.inset, HistoryView.inset),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  RoundButton(
                    'left',
                    size: 28,
                    tooltip: _searching ? 'Retour à l’historique' : 'Retour à l’accueil',
                    onPressed: _back,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _searching ? 'Recherche' : 'Historique',
                    style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text),
                  ),
                  const Spacer(),
                  if (!_searching || query.isNotEmpty)
                    Text(
                      query.isEmpty ? '${rows.length}' : '${rows.length} / ${widget.rows.length}',
                      style: uiText(TextSize.badge, color: ui.text2, tabular: true),
                    ),
                  const SizedBox(width: 12),
                  RoundButton('x', size: 24, ghost: true, tooltip: 'Fermer l’historique', onPressed: widget.onClose),
                ],
              ),
              if (!_dedicated || _searching)
                SizedBox(
                  width: 280,
                  child: SearchField(
                    small: true,
                    autofocus: _dedicated && _searching,
                    icon: 'search',
                    placeholder: 'Chercher dans l’historique',
                    controller: _search,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _panel(_results(ui, rows, query))),
      ],
    ),
  );

  Widget _panel(Widget child, {bool fused = false}) => Surface(
    key: const ValueKey('history-top-list'),
    color: fused ? null : MikkyUi.of(context).island,
    radius: HistoryView.radius,
    shadows: fused ? const [] : MikkyUi.of(context).floating,
    child: ClipRRect(borderRadius: BorderRadius.circular(HistoryView.radius), child: child),
  );

  Widget _results(MikkyUi ui, List<HistoryRow> rows, String query) => rows.isEmpty
      ? Center(
          child: Text(
            query.isEmpty ? 'Aucune conversation' : 'Rien trouvé',
            style: uiText(TextSize.caption, color: ui.text2),
          ),
        )
      : Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: _dedicated ? 4 : 8),
          child: HistoryScroll(key: ValueKey(query), child: _grid(rows)),
        );

  Widget _fullHeight(MikkyUi ui, List<HistoryRow> rows, String query) => Padding(
    padding: const EdgeInsets.all(HistoryView.inset),
    child: HistoryDetach(
      navigation: _HistoryNavigation(
        searching: _searching,
        count: query.isEmpty ? '${widget.rows.length}' : '${rows.length}/${widget.rows.length}',
        onBack: _back,
        onSearch: () => setState(() => _searching = true),
      ),
      body: KeyedSubtree(
        key: const ValueKey('history-content'),
        child: _panel(
          Padding(
            padding: const EdgeInsets.all(4),
            child: _searching
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        child: Center(
                          child: SearchField(
                            small: true,
                            autofocus: true,
                            icon: 'search',
                            placeholder: 'Chercher dans l’historique',
                            controller: _search,
                          ),
                        ),
                      ),
                      Expanded(child: query.isEmpty ? _SearchWelcome(ui) : _results(ui, rows, query)),
                    ],
                  )
                : _results(ui, rows, query),
          ),
          fused: true,
        ),
      ),
    ),
  );

  Widget _grid(List<HistoryRow> rows) {
    final items = [for (final row in rows) _row(row)];
    return SlidingHover(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i += widget.columns)
            Row(
              children: [
                for (var column = 0; column < widget.columns; column++) ...[
                  if (column > 0) const SizedBox(width: 16),
                  Expanded(
                    child: i + column < items.length
                        ? items[i + column]
                        : const SizedBox(height: HistoryView.rowHeight),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _row(HistoryRow row) => _HistoryRow(
    key: ValueKey(row.id),
    row: row,
    onOpen: widget.onOpen == null ? null : () => widget.onOpen!(row.id),
    onMenu: widget.onMenu == null ? null : () => widget.onMenu!(row.id),
  );
}

class _SearchWelcome extends StatelessWidget {
  const _SearchWelcome(this.ui);

  final MikkyUi ui;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MikkyIcon('search', size: 26, color: ui.text3),
        const SizedBox(height: 8),
        Text(
          'Retrouver une conversation',
          style: uiText(TextSize.small, weight: FontWeight.w500, color: ui.text),
        ),
        const SizedBox(height: 4),
        Text('Saisis quelques mots de son titre.', style: uiText(TextSize.caption, color: ui.text2)),
      ],
    ),
  );
}

/// Detached leading controls stay fixed beside the history and search.
class _HistoryNavigation extends StatelessWidget {
  const _HistoryNavigation({
    required this.searching,
    required this.count,
    required this.onBack,
    required this.onSearch,
  });

  final bool searching;
  final String count;
  final VoidCallback onBack, onSearch;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Surface(
      key: const ValueKey('history-navigation'),
      width: 40,
      radius: HistoryView.radius,
      // HistoryDetach paints both surfaces as one shape while joined.
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          RoundButton(
            'left',
            size: 32,
            ghost: true,
            tooltip: searching ? 'Retour à l’historique' : 'Retour à l’accueil',
            onPressed: onBack,
          ),
          const SizedBox(height: 8),
          Semantics(
            selected: searching,
            child: RoundButton(
              'search',
              key: const ValueKey('history-search-entry'),
              size: 32,
              ghost: !searching,
              ink: searching,
              tooltip: 'Rechercher dans l’historique',
              onPressed: onSearch,
            ),
          ),
          const Spacer(),
          Semantics(
            label: searching ? 'Résultats : $count' : 'Historique : $count conversations',
            excludeSemantics: true,
            child: Column(
              children: [
                MikkyIcon('history', size: 12, color: ui.text3),
                const SizedBox(height: 4),
                FittedBox(
                  child: Text(count, style: uiText(TextSize.badge, mono: true, color: ui.text2, tabular: true)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({super.key, required this.row, this.onOpen, this.onMenu});

  final HistoryRow row;
  final VoidCallback? onOpen, onMenu;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return HoverTarget(
      child: Semantics(
        button: true,
        child: GestureDetector(
          onSecondaryTap: onMenu,
          child: Pressable(
            onTap: onOpen,
            // Keep the menu anchor fixed when its nested button is pressed.
            // The menu button already supplies its own press animation.
            pressedScale: 1,
            child: HoverBuilder(
              builder: (context, hover) => SizedBox(
                height: HistoryView.rowHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      BrandLogo(row.brand, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    row.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: uiText(
                                      TextSize.small,
                                      weight: FontWeight.w500,
                                      color: hover ? ui.text : ui.text2,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                if (row.working) ...[const SizedBox(width: 6), const HistoryActivity()],
                              ],
                            ),
                            Text(row.when, style: uiText(TextSize.caption, color: ui.text3, height: 1.2)),
                          ],
                        ),
                      ),
                      if (onMenu != null) ...[
                        const SizedBox(width: 4),
                        RoundButton.menu(size: 28, tooltip: 'Menu de ${row.title}', onPressed: onMenu),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
