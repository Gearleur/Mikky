import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

String _ops(LineDiff d) => d.lines.map((l) => l.toString()).join('|');

void main() {
  group('lineDiff', () {
    test('a new file: every line added, numbered', () {
      final d = lineDiff(null, 'a\nb\n');
      expect(d.isNew, isTrue);
      expect(d.label, '+2 −0');
      expect(d.lines.map((l) => l.newLine), [1, 2]);
    });

    test('nothing changed', () {
      final d = lineDiff('a\nb', 'a\nb');
      expect(d.added + d.removed, 0);
      expect(_ops(d), ' a| b');
    });

    test('one line changed in the middle: removed, then added', () {
      final d = lineDiff('a\nb\nc\nd', 'a\nB\nc\nd');
      expect(_ops(d), ' a|-b|+B| c| d');
      expect(d.label, '+1 −1');
      final changed = d.lines.where((l) => l.op != DiffOp.same).toList();
      expect(changed[0].oldLine, 2);
      expect(changed[1].newLine, 2);
    });

    test('the smallest change: lines moved around keep what they can', () {
      final d = lineDiff('x\ny\nz', 'x\nnew\ny');
      expect(d.label, '+1 −1');
      expect(_ops(d), ' x|+new| y|-z');
      // Same counts as diffStat (both the smallest change).
      for (final (before, after) in [
        ('a\nb\nc\nd\ne', 'e\nd\nc\nb\na'),
        ('abcabba'.split('').join('\n'), 'cbabac'.split('').join('\n')),
      ]) {
        final s = diffStat(FileDiff('f', before, after));
        final l = lineDiff(before, after);
        expect((l.added, l.removed), (s.added, s.removed));
      }
    });

    test('Windows line ends do not count as changes', () {
      expect(lineDiff('a\r\nb\r\n', 'a\nb\n').added, 0);
    });

    test('numbers after the change follow both files', () {
      final d = lineDiff('a\nb\nc', 'a\nnew\nb\nc');
      final c = d.lines.last;
      expect((c.oldLine, c.newLine), (3, 4));
    });

    test('too many changes: approximate, every line still there', () {
      final before = List.generate(3000, (i) => 'old $i').join('\n');
      final after = List.generate(3000, (i) => 'new $i').join('\n');
      final d = lineDiff(before, after);
      expect(d.approximate, isTrue);
      expect(d.removed, 3000);
      expect(d.added, 3000);
    });

    test('a big file with one change is exact and quick', () {
      final before = List.generate(20000, (i) => 'line $i').join('\n');
      final after = List.generate(20000, (i) => i == 12345 ? 'changed' : 'line $i').join('\n');
      final watch = Stopwatch()..start();
      final d = lineDiff(before, after);
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(d.approximate, isFalse);
      expect(d.label, '+1 −1');
    });

    test('kept with its change: computed once', () {
      const f = FileDiff('a', 'a', 'b');
      expect(identical(diffOf(f), diffOf(f)), isTrue);
    });
  });

  group('chunks', () {
    final before = List.generate(30, (i) => 'l$i').join('\n');
    final after = List.generate(30, (i) => i == 15 ? 'changed' : 'l$i').join('\n');

    test('a change with 3 lines around it, the rest folded', () {
      final chunks = lineDiff(before, after).chunks();
      expect(chunks.map((c) => c.runtimeType), [DiffFolded, DiffShown, DiffFolded]);
      expect(chunks[0].lines.length, 12);
      expect(chunks[1].lines.length, 3 + 2 + 3);
      expect(chunks[2].lines.length, 11);
    });

    test('a short run between two changes stays shown', () {
      final after2 = List.generate(30, (i) => i == 15 || i == 20 ? 'changed' : 'l$i').join('\n');
      final chunks = lineDiff(before, after2).chunks();
      expect(chunks.whereType<DiffShown>(), hasLength(1));
    });

    test('nothing folded when everything is a change', () {
      expect(lineDiff(null, 'a\nb').chunks().single, isA<DiffShown>());
    });
  });
}
