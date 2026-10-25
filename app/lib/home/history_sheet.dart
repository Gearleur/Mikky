import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../ui/content/history_row.dart';
import '../ui/content/history_view.dart';
import '../ui/overlays/sheet.dart';

export '../ui/content/history_row.dart';

/// A menu action receives the sheet's context, for an anchored menu.
typedef HistoryMenu = void Function(BuildContext within, String id);

/// The selected history page, shared by the app and board previews.
/// Its query and scroll survive live updates; subscriptions end with it.
Future<void> showHistory(
  BuildContext within, {
  required List<HistoryRow> rows,
  Listenable? updates,
  List<HistoryRow> Function()? readRows,
  ValueChanged<String>? onOpen,
  HistoryMenu? onMenu,
  HistorySearchMode searchMode = HistorySearchMode.dedicated,
  int columns = 1,
  bool initiallySearching = false,
}) async {
  final current = ValueNotifier(readRows?.call() ?? rows);
  void refresh() {
    final next = readRows?.call() ?? rows;
    if (!listEquals(current.value, next)) current.value = next;
  }

  updates?.addListener(refresh);
  try {
    await showSheetPage(
      within,
      builder: (context) => ValueListenableBuilder<List<HistoryRow>>(
        valueListenable: current,
        builder: (context, rows, _) => HistoryView(
          rows: rows,
          searchMode: searchMode,
          columns: columns,
          initiallySearching: initiallySearching,
          onClose: () => Sheet.close(context),
          onOpen: (id) {
            Sheet.close(context);
            onOpen?.call(id);
          },
          onMenu: onMenu == null ? null : (id) => onMenu(context, id),
        ),
      ),
    );
  } finally {
    updates?.removeListener(refresh);
    current.dispose();
  }
}
