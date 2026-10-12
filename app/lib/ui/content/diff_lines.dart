import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../foundation/motion.dart';
import '../foundation/tokens.dart';
import '../pixels/dot_surface.dart';
import '../pixels/pixel_fx.dart';

/// A diff's colours (2026-10-12, chosen: « grain »): an added line in our
/// blues, a removed one in our oranges, lightest first; on black, a tint
/// lighter.
(List<Color>, List<Color>) diffTints(MikkyUi ui) =>
    (PixelFxPalette.signatureBlue.onWindow(ui).levels, PixelFxPalette.signatureOrange.onWindow(ui).levels);

/// The colour of an added line, of a removed one: our blue, our orange
/// (« +3 −1 », « Nouveau fichier »).
(Color, Color) diffColours(MikkyUi ui) {
  final (blues, oranges) = diffTints(ui);
  return (blues[1], oranges[1]);
}

/// One line of a diff (2026-10-12, chosen: « grain »), a piece of a
/// [DotSurface]: its number, then its text in mono. Added: a light tint of
/// our blue and, beside its number, a grain of our blues ([PixelEdge.change])
/// that goes on along the [run] of changed lines it is in. Removed: the
/// same in our oranges. The changed text stands out (medium, the brightest
/// ink), the rest is quieter.
class DiffLineRow extends StatelessWidget {
  const DiffLineRow(this.line, {super.key, this.first = false, this.last = false, this.digits = 2, this.run = (0, 1)});

  final DiffLine line;

  /// First and last of its block: its ends are round.
  final bool first, last;

  /// The widest number's digits; 0: no numbers (an excerpt, its place in
  /// the file unknown).
  final int digits;

  /// Which of its run of changed lines it is, and how many there are.
  final (int, int) run;

  /// A line is 18 px: three steps of the dots' grid, six of the grain's.
  static const _line = 18.0;

  /// Where the numbers end; where the code starts, past the grain.
  static double _numbersEnd(int digits) => 4 + digits * 7.0;
  static double codeAt(int digits) => _numbersEnd(digits) + 26;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final (blues, oranges) = diffTints(ui);
    final colours = switch (line.op) {
      DiffOp.added => blues,
      DiffOp.removed => oranges,
      DiffOp.same => null,
    };
    final end = _numbersEnd(digits);
    final number = line.newLine ?? line.oldLine;
    final mono = uiText(TextSize.caption, mono: true, height: _line / TextSize.caption);
    return CustomPaint(
      painter: DotSurfacePainter(
        ui,
        first: first,
        last: last,
        fill: colours?[1].withValues(alpha: ui.isLight ? .1 : .2),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, first ? 6 : 0, 10, last ? 6 : 0),
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: end,
                  child: Text(
                    number == null || digits == 0 ? '' : '$number',
                    textAlign: TextAlign.right,
                    style: mono.copyWith(
                      color: colours != null ? ui.text2 : ui.text3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 26),
                Expanded(
                  child: Text(
                    line.text.isEmpty ? ' ' : line.text.replaceAll('\t', '  '),
                    style: colours != null
                        ? mono.copyWith(color: ui.text, fontWeight: FontWeight.w500)
                        : mono.copyWith(color: ui.text2),
                  ),
                ),
              ],
            ),
            if (colours != null)
              Positioned(
                left: end + 7,
                top: 0,
                bottom: 0,
                child: PixelEdge.change(colours, run: run, rowsPerLine: (_line / PixelEdge.step).round()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lines folded away, a piece of a [DotSurface]: unchanged ones, or the
/// [rest] past the lines shown; a click shows them ([onTap]).
class DiffFoldRow extends StatelessWidget {
  const DiffFoldRow({
    super.key,
    required this.count,
    required this.left,
    this.onTap,
    this.rest = false,
    this.first = false,
    this.last = false,
  });

  final int count;
  final VoidCallback? onTap;
  final bool rest, first, last;

  /// Where its text starts.
  final double left;

  /// Four steps of the dots' grid: the grid goes on through it.
  static const height = DotSurface.step * 4;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return HoverBuilder(
      enabled: onTap != null,
      builder: (context, hover) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: CustomPaint(
            painter: DotSurfacePainter(ui, first: first, last: last, fill: hover ? ui.hover : null),
            child: Container(
              height: height + (first ? 6 : 0) + (last ? 6 : 0),
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.fromLTRB(left, first ? 6 : 0, 10, last ? 6 : 0),
              child: Text(
                rest
                    ? (count == 1 ? '… 1 ligne de plus' : '… $count lignes de plus')
                    : (count == 1 ? '… 1 ligne inchangée' : '… $count lignes inchangées'),
                style: uiText(TextSize.caption, color: hover ? ui.text2 : ui.text3, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of a diff's block, flattened for a list ([diffRows]): a line,
/// or lines folded away. [first] and [last]: the block's round ends.
sealed class DiffRow {
  const DiffRow({required this.first, required this.last});

  final bool first, last;
}

/// A line, and which of its run of changed lines it is (how many there
/// are): the grain goes on along the run.
class DiffLineItem extends DiffRow {
  const DiffLineItem(this.line, this.run, {required super.first, required super.last});

  final DiffLine line;
  final (int, int) run;
}

/// Lines folded away: unchanged ([chunk]: which chunk, to open it), or the
/// rest past the lines shown ([chunk] null).
class DiffFoldItem extends DiffRow {
  const DiffFoldItem(this.count, this.chunk, {required super.first, required super.last});

  final int count;
  final int? chunk;
}

/// The rows of [chunks]: each line with its run; each folded chunk one
/// fold, unless [opened] says it is open; past [maxLines] lines, one fold
/// for the rest.
List<DiffRow> diffRows(List<DiffChunk> chunks, {bool Function(int chunk)? opened, int? maxLines}) {
  final items = <(DiffLine?, (int, int), int, int?)>[];
  var shown = 0;
  var rest = 0;
  for (var k = 0; k < chunks.length; k++) {
    final lines = chunks[k].lines;
    if (chunks[k] is DiffFolded && !(opened?.call(k) ?? false)) {
      if (maxLines != null && shown >= maxLines) {
        rest += lines.length;
      } else {
        items.add((null, (0, 1), lines.length, k));
      }
      continue;
    }
    for (var i = 0; i < lines.length; i++) {
      if (maxLines != null && shown >= maxLines) {
        rest++;
        continue;
      }
      shown++;
      // Its run: the changed lines of its kind around it.
      var from = i, to = i;
      if (lines[i].op != DiffOp.same) {
        while (from > 0 && lines[from - 1].op == lines[i].op) {
          from--;
        }
        while (to < lines.length - 1 && lines[to + 1].op == lines[i].op) {
          to++;
        }
      }
      items.add((lines[i], (i - from, to - from + 1), 0, k));
    }
  }
  if (rest > 0) items.add((null, (0, 1), rest, null));
  return [
    for (final (i, (line, run, count, chunk)) in items.indexed)
      line != null
          ? DiffLineItem(line, run, first: i == 0, last: i == items.length - 1)
          : DiffFoldItem(count, chunk, first: i == 0, last: i == items.length - 1),
  ];
}

/// [row] as a widget, its numbers [digits] wide; a fold opens with [onFold]
/// (null: it does not open).
Widget diffRowView(DiffRow row, {required int digits, ValueChanged<DiffFoldItem>? onFold}) => switch (row) {
  DiffLineItem(:final line, :final run) => DiffLineRow(
    line,
    first: row.first,
    last: row.last,
    digits: digits,
    run: run,
  ),
  DiffFoldItem() => DiffFoldRow(
    count: row.count,
    rest: row.chunk == null,
    first: row.first,
    last: row.last,
    // Under the code, past the numbers.
    left: DiffLineRow.codeAt(digits),
    onTap: onFold == null ? null : () => onFold(row),
  ),
};

/// The widest line number of [diffs] in digits, for their column of
/// numbers; 0 when one is an excerpt whose place in the file is unknown.
int diffDigits(List<FileDiff> changes) {
  if (!changes.every((c) => c.numbered)) return 0;
  var widest = 0;
  for (final c in changes) {
    for (final l in diffOf(c).lines) {
      final n = l.newLine ?? l.oldLine ?? 0;
      if (n > widest) widest = n;
    }
  }
  return '$widest'.length;
}
