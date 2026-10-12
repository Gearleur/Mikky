import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../controls/buttons.dart';
import '../foundation/motion.dart';
import '../foundation/tokens.dart';
import '../pixels/dot_surface.dart';
import 'diff_lines.dart';
import 'side.dart';

/// Opens the diff of a file from anywhere below (2026-10-08: a click on
/// `+N −M` in a request or in an agent's thread): its name, and its
/// changes (several when the agent touched it more than once).
typedef OpenDiff = void Function(String path, List<FileDiff> changes);

/// Who opens a diff for the widgets below (the island's window: a page).
class DiffOpener extends InheritedWidget {
  const DiffOpener({super.key, required this.open, required super.child});

  final OpenDiff open;

  static OpenDiff? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DiffOpener>()?.open;

  @override
  bool updateShouldNotify(DiffOpener old) => old.open != open;
}

/// « +12 −3 » in our blue and our orange ([diffColours]), in mono. With
/// [onTap] (or a [DiffOpener] above and [changes]), it opens the diff:
/// underlined under the mouse.
class DiffCount extends StatelessWidget {
  const DiffCount({
    super.key,
    required this.added,
    required this.removed,
    this.path,
    this.changes,
    this.onTap,
    this.size = TextSize.caption,
    this.hideZero = false,
  });

  /// The counts of [changes], whole.
  factory DiffCount.of(
    String path,
    List<FileDiff> changes, {
    Key? key,
    double size = TextSize.caption,
    bool hideZero = false,
  }) {
    var added = 0, removed = 0;
    for (final c in changes) {
      final d = diffOf(c);
      added += d.added;
      removed += d.removed;
    }
    return DiffCount(
      key: key,
      added: added,
      removed: removed,
      path: path,
      changes: changes,
      size: size,
      hideZero: hideZero,
    );
  }

  final int added, removed;
  final String? path;
  final List<FileDiff>? changes;
  final VoidCallback? onTap;
  final double size;

  /// « +3 » alone when nothing was removed.
  final bool hideZero;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final opener = DiffOpener.maybeOf(context);
    final tap = onTap ?? (opener != null && changes != null && path != null ? () => opener(path!, changes!) : null);
    final (plus, minus) = diffColours(ui);
    Widget text(bool hover) {
      final style = uiText(
        size,
        mono: true,
        tabular: true,
      ).copyWith(decoration: hover ? TextDecoration.underline : null, decorationColor: ui.text3);
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '+$added',
              style: style.copyWith(color: plus),
            ),
            if (!hideZero || removed > 0) ...[
              const TextSpan(text: ' '),
              TextSpan(
                text: '−$removed',
                style: style.copyWith(color: minus),
              ),
            ],
          ],
        ),
      );
    }

    if (tap == null) return text(false);
    return Semantics(
      button: true,
      label: 'Voir les changements',
      child: HoverBuilder(
        builder: (context, hover) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: text(hover)),
          ),
        ),
      ),
    );
  }
}

/// One row of a diff page, flattened for a lazy list: a heading, or a
/// row of one of its changes.
sealed class _Row {
  const _Row();
}

class _Head extends _Row {
  const _Head(this.label);

  final String label;
}

class _Item extends _Row {
  const _Item(this.change, this.row);

  final int change;
  final DiffRow row;
}

/// The diff of one file (2026-10-08, « un clic sur +N −M ouvre le diff du
/// fichier »): its name and where it is, `+N −M`, then its lines in mono
/// numbered, on a surface of dots ([DotSurface]) — added in our blues,
/// removed in our oranges ([DiffLineRow]), a few unchanged around each
/// change; longer unchanged runs folded (« 24 lignes inchangées », a click
/// unfolds them). A lazy list: only what shows is built, however big the
/// file. Several changes of the same file follow each other
/// (« Modification 2 sur 3 »).
class DiffPage extends StatefulWidget {
  const DiffPage({super.key, required this.path, required this.changes, required this.back, this.scroll});

  final String path;
  final List<FileDiff> changes;
  final VoidCallback back;
  final ScrollController? scroll;

  @override
  State<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends State<DiffPage> {
  /// Folds opened by the user: (change, chunk).
  final _open = <(int, int)>{};
  late List<LineDiff> _diffs = [for (final c in widget.changes) diffOf(c)];

  @override
  void didUpdateWidget(DiffPage old) {
    super.didUpdateWidget(old);
    if (old.changes != widget.changes) _diffs = [for (final c in widget.changes) diffOf(c)];
  }

  List<_Row> _rows() => [
    for (var c = 0; c < _diffs.length; c++) ...[
      if (_diffs.length > 1) _Head('Modification ${c + 1} sur ${_diffs.length}'),
      for (final row in diffRows(_diffs[c].chunks(), opened: (k) => _open.contains((c, k)))) _Item(c, row),
      if (_diffs[c].chunks().isEmpty) const _Head('Rien n’a changé'),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final name = widget.path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ?? widget.path;
    final folder = widget.path.length > name.length ? widget.path.substring(0, widget.path.length - name.length) : '';
    final approximate = _diffs.any((d) => d.approximate);
    final rows = _rows();
    final digits = diffDigits(widget.changes);
    final head = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(TextSize.heading, weight: FontWeight.w600, color: ui.text, height: 1.3),
                ),
              ),
              const SizedBox(width: 10),
              DiffCount.of(widget.path, widget.changes, size: TextSize.label, hideZero: true),
            ],
          ),
          if (folder.isNotEmpty)
            Text(
              folder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: uiText(TextSize.caption, color: ui.text3, mono: true, height: 1.5),
            ),
          if (_diffs.length == 1 && _diffs.first.isNew)
            Text('Nouveau fichier', style: uiText(TextSize.caption, color: diffColours(ui).$1, height: 1.5)),
          if (approximate)
            Text(
              'Trop de changements pour les suivre ligne à ligne : l’avant, puis l’après.',
              style: uiText(TextSize.caption, color: ui.text3, height: 1.5),
            ),
        ],
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) {
              final room = box.maxWidth - 32;
              final width = room < readingWidth ? room : readingWidth;
              final l = (box.maxWidth - width) / 2;
              return ListView.builder(
                controller: widget.scroll,
                padding: EdgeInsets.fromLTRB(l, 62, box.maxWidth - l - width, 24),
                itemCount: rows.length + 1,
                itemBuilder: (context, i) => i == 0 ? head : _row(ui, rows[i - 1], digits),
              );
            },
          ),
        ),
        const Positioned(top: 0, left: 0, right: 0, child: TopBlur()),
        SideHead(
          leading: RoundButton('left', size: 34, onPressed: widget.back, tooltip: 'Retour'),
        ),
      ],
    );
  }

  Widget _row(MikkyUi ui, _Row row, int digits) => switch (row) {
    _Head(:final label) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        label,
        style: uiText(TextSize.small, weight: FontWeight.w500, color: ui.text3),
      ),
    ),
    _Item(:final change, :final row) => diffRowView(
      row,
      digits: digits,
      onFold: (fold) => setState(() => _open.add((change, fold.chunk!))),
    ),
  };
}

/// A file's change in a few lines (2026-10-12, in an agent's thread):
/// its changed lines with one unchanged line around them, at most
/// [maxLines], on the surface of dots; the rest folded. A fold opens the
/// whole diff, with a [DiffOpener] above.
class DiffPreview extends StatelessWidget {
  const DiffPreview(this.diff, {super.key, this.maxLines = 10});

  final FileDiff diff;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final open = DiffOpener.maybeOf(context);
    final digits = diffDigits([diff]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in diffRows(diffOf(diff).chunks(context: 1), maxLines: maxLines))
          diffRowView(row, digits: digits, onFold: open == null ? null : (_) => open(diff.path, [diff])),
      ],
    );
  }
}
