import 'dart:typed_data';

import 'session_event.dart';

/// What a line of a [LineDiff] is.
enum DiffOp { same, added, removed }

/// One line of a diff, with its number before ([oldLine]) and after
/// ([newLine]), from 1; null where it does not exist.
class DiffLine {
  const DiffLine(this.op, this.text, {this.oldLine, this.newLine});

  final DiffOp op;
  final String text;
  final int? oldLine, newLine;

  @override
  bool operator ==(Object other) =>
      other is DiffLine && other.op == op && other.text == text && other.oldLine == oldLine && other.newLine == newLine;

  @override
  int get hashCode => Object.hash(op, text, oldLine, newLine);

  @override
  String toString() =>
      '${switch (op) {
        DiffOp.same => ' ',
        DiffOp.added => '+',
        DiffOp.removed => '-',
      }}$text';
}

/// A run of lines to show, or unchanged lines folded away.
sealed class DiffChunk {
  const DiffChunk(this.lines);

  final List<DiffLine> lines;
}

/// Lines shown: changes and a little of what surrounds them.
class DiffShown extends DiffChunk {
  const DiffShown(super.lines);
}

/// Unchanged lines folded (« 24 lignes inchangées »), shown on demand.
class DiffFolded extends DiffChunk {
  const DiffFolded(super.lines);
}

/// Every line of a file change, in order: kept, added, removed (removed
/// lines before the added ones that replace them).
class LineDiff {
  const LineDiff(
    this.lines, {
    required this.added,
    required this.removed,
    this.approximate = false,
    this.isNew = false,
  });

  final List<DiffLine> lines;
  final int added, removed;

  /// Too many changes to compare line by line (more than
  /// [lineDiffMaxEdits]): what differs between the same start and the same
  /// end is shown as removed, then added. The counts are then too high.
  final bool approximate;

  /// A new file: every line added.
  final bool isNew;

  /// « +12 −3 ».
  String get label => '+$added −$removed';

  /// The lines to show: each change with [context] unchanged lines around
  /// it; longer unchanged runs between them folded. Unchanged runs shorter
  /// than a fold are not worth folding: they stay shown.
  List<DiffChunk> chunks({int context = 3}) {
    if (lines.isEmpty) return const [];
    final out = <DiffChunk>[];
    var shown = <DiffLine>[];
    var i = 0;
    while (i < lines.length) {
      if (lines[i].op != DiffOp.same) {
        shown.add(lines[i++]);
        continue;
      }
      var j = i;
      while (j < lines.length && lines[j].op == DiffOp.same) {
        j++;
      }
      // An unchanged run [i, j): kept near the changes around it.
      final atStart = i == 0, atEnd = j == lines.length;
      final keepBefore = atStart ? 0 : context, keepAfter = atEnd ? 0 : context;
      final run = j - i;
      if (run <= keepBefore + keepAfter + 1) {
        shown.addAll(lines.sublist(i, j));
      } else {
        shown.addAll(lines.sublist(i, i + keepBefore));
        if (shown.isNotEmpty) out.add(DiffShown(shown));
        shown = [];
        out.add(DiffFolded(lines.sublist(i + keepBefore, j - keepAfter)));
        shown.addAll(lines.sublist(j - keepAfter, j));
      }
      i = j;
    }
    if (shown.isNotEmpty) out.add(DiffShown(shown));
    return out;
  }
}

/// Beyond this many changes, no exact comparison (see [LineDiff.approximate]):
/// its memory grows as their square.
const lineDiffMaxEdits = 1200;

/// Beyond this many lines in both texts, no comparison at all: the middle
/// is removed, then added.
const lineDiffMaxLines = 60000;

final _cache = Expando<LineDiff>('lineDiff');

/// The diff of [d], computed once per change (kept with it); its lines
/// numbered from [FileDiff.line] when known.
LineDiff diffOf(FileDiff d) => _cache[d] ??= lineDiff(d.oldText, d.newText, from: d.line ?? 1);

/// Line by line, what [after] changes in [before] (null: a new file), the
/// smallest change (Myers' algorithm, after the same start and the same
/// end are set aside), its lines numbered [from] there. Bounded: see
/// [lineDiffMaxEdits].
LineDiff lineDiff(String? before, String after, {int from = 1}) {
  final diff = _lineDiff(before, after);
  if (from == 1) return diff;
  final shift = from - 1;
  return LineDiff(
    [
      for (final l in diff.lines)
        DiffLine(
          l.op,
          l.text,
          oldLine: l.oldLine == null ? null : l.oldLine! + shift,
          newLine: l.newLine == null ? null : l.newLine! + shift,
        ),
    ],
    added: diff.added,
    removed: diff.removed,
    approximate: diff.approximate,
    isNew: diff.isNew,
  );
}

LineDiff _lineDiff(String? before, String after) {
  final b = before == null ? const <String>[] : splitLines(before);
  final a = splitLines(after);
  if (before == null || b.isEmpty) {
    return LineDiff(
      [for (var i = 0; i < a.length; i++) DiffLine(DiffOp.added, a[i], newLine: i + 1)],
      added: a.length,
      removed: 0,
      isNew: before == null,
    );
  }
  var start = 0;
  while (start < b.length && start < a.length && b[start] == a[start]) {
    start++;
  }
  var endB = b.length, endA = a.length;
  while (endB > start && endA > start && b[endB - 1] == a[endA - 1]) {
    endB--;
    endA--;
  }
  final out = <DiffLine>[for (var i = 0; i < start; i++) DiffLine(DiffOp.same, b[i], oldLine: i + 1, newLine: i + 1)];
  var approximate = false;
  final middle = b.length + a.length > lineDiffMaxLines ? null : _myers(b, start, endB, a, start, endA);
  if (middle == null) {
    approximate = true;
    for (var i = start; i < endB; i++) {
      out.add(DiffLine(DiffOp.removed, b[i], oldLine: i + 1));
    }
    for (var j = start; j < endA; j++) {
      out.add(DiffLine(DiffOp.added, a[j], newLine: j + 1));
    }
  } else {
    out.addAll(middle);
  }
  for (var k = 0; k < b.length - endB; k++) {
    out.add(DiffLine(DiffOp.same, b[endB + k], oldLine: endB + k + 1, newLine: endA + k + 1));
  }
  var added = 0, removed = 0;
  for (final l in out) {
    if (l.op == DiffOp.added) added++;
    if (l.op == DiffOp.removed) removed++;
  }
  return LineDiff(out, added: added, removed: removed, approximate: approximate);
}

/// The lines of [text]: `\r\n` or `\n`; no last empty line for a final
/// line break.
List<String> splitLines(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.endsWith('\r')) lines[i] = l.substring(0, l.length - 1);
  }
  return lines;
}

/// Myers' diff of `b[b0, b1)` against `a[a0, a1)`, or null past
/// [lineDiffMaxEdits]. Removed lines come before added ones.
List<DiffLine>? _myers(List<String> b, int b0, int b1, List<String> a, int a0, int a1) {
  final n = b1 - b0, m = a1 - a0;
  if (n == 0 && m == 0) return const [];
  final max = n + m;
  final limit = max < lineDiffMaxEdits ? max : lineDiffMaxEdits;
  // v[k + offset]: the furthest x on diagonal k; one copy per step d.
  final offset = limit + 1;
  final v = Int32List(2 * limit + 3);
  final trace = <Int32List>[];
  int? found;
  for (var d = 0; d <= limit; d++) {
    trace.add(Int32List.fromList(v));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])) {
        x = v[k + 1 + offset]; // down: an added line
      } else {
        x = v[k - 1 + offset] + 1; // right: a removed line
      }
      var y = x - k;
      while (x < n && y < m && b[b0 + x] == a[a0 + y]) {
        x++;
        y++;
      }
      v[k + offset] = x;
      if (x >= n && y >= m) {
        found = d;
        break;
      }
    }
    if (found != null) break;
  }
  if (found == null) return null;
  // Back from the end, step by step.
  final reversed = <DiffLine>[];
  var x = n, y = m;
  for (var d = found; d > 0; d--) {
    final vd = trace[d];
    final k = x - y;
    final down = k == -d || (k != d && vd[k - 1 + offset] < vd[k + 1 + offset]);
    final prevK = down ? k + 1 : k - 1;
    final prevX = vd[prevK + offset];
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      x--;
      y--;
      reversed.add(DiffLine(DiffOp.same, b[b0 + x], oldLine: b0 + x + 1, newLine: a0 + y + 1));
    }
    if (down) {
      y--;
      reversed.add(DiffLine(DiffOp.added, a[a0 + y], newLine: a0 + y + 1));
    } else {
      x--;
      reversed.add(DiffLine(DiffOp.removed, b[b0 + x], oldLine: b0 + x + 1));
    }
  }
  while (x > 0 && y > 0) {
    x--;
    y--;
    reversed.add(DiffLine(DiffOp.same, b[b0 + x], oldLine: b0 + x + 1, newLine: a0 + y + 1));
  }
  final out = reversed.reversed.toList();
  // Within each run of changes, removed lines first (as one reads a
  // replacement).
  final sorted = <DiffLine>[];
  var i = 0;
  while (i < out.length) {
    if (out[i].op == DiffOp.same) {
      sorted.add(out[i++]);
      continue;
    }
    final removed = <DiffLine>[], added = <DiffLine>[];
    while (i < out.length && out[i].op != DiffOp.same) {
      (out[i].op == DiffOp.removed ? removed : added).add(out[i]);
      i++;
    }
    sorted
      ..addAll(removed)
      ..addAll(added);
  }
  return sorted;
}
