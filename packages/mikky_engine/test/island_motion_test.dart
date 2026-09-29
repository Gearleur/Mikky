import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void run(IslandMotion m, double seconds) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    m.update(1 / 60);
  }
}

void main() {
  group('top', () {
    test('starts hidden and still', () {
      final m = IslandMotion();
      expect(m.isGone, isTrue);
      expect(m.visibility, 0);
    });

    test('compact: 186 × 36, radius 18, small Mikky', () {
      final m = IslandMotion()..setShape(IslandShape.compact);
      run(m, 2);
      expect(m.isAtRest, isTrue);
      expect(m.currentWidth, 186);
      expect(m.currentHeight, 36);
      expect(m.cornerRadius, 18);
      expect(m.mikkyRadius, 9);
      expect(m.compactContentOpacity, 1);
    });

    test('on opening, the height waits 45 ms for the width', () {
      final m = IslandMotion()..setShape(IslandShape.compact);
      run(m, 2);
      m.setShape(IslandShape.open);
      run(m, 2 / 60);
      expect(m.currentWidth, greaterThan(186));
      expect(m.currentHeight, 36);
      run(m, 2);
      expect(m.currentWidth, 430);
      expect(m.currentHeight, 178);
      expect(m.cornerRadius, 30);
      expect(m.mikkyRadius, 28);
      expect(m.openContentOpacity, 1);
    });

    test('the list layout is a bit bigger', () {
      final m = IslandMotion()..setShape(IslandShape.open, layout: IslandLayout.list);
      run(m, 2);
      expect(m.currentWidth, 450);
      expect(m.currentHeight, 180);
    });

    test('hiding slides Mikky up with the island', () {
      final m = IslandMotion()..setShape(IslandShape.compact);
      run(m, 2);
      m.setShape(IslandShape.hidden);
      run(m, .1);
      expect(m.mikkyY, lessThan(20));
      run(m, 2);
      expect(m.isGone, isTrue);
    });
  });

  group('right', () {
    test('compact is a small tab, visible once it has its width', () {
      final m = IslandMotion(edge: IslandEdge.right)..setShape(IslandShape.compact);
      run(m, 2);
      expect((m.currentWidth, m.currentHeight), (64, 92));
      expect(m.visibility, 1);
      expect(m.mikkyRadius, 13);
    });

    test('open is a portrait card, taller than wide', () {
      final m = IslandMotion(edge: IslandEdge.right)..setShape(IslandShape.compact);
      run(m, 2);
      m.setShape(IslandShape.open);
      run(m, 2 / 60);
      // The depth (width, away from the edge) waits for the length.
      expect(m.currentHeight, greaterThan(92));
      expect(m.currentWidth, 64);
      run(m, 2);
      expect((m.currentWidth, m.currentHeight), (320, 560));
      expect(m.currentHeight, greaterThan(m.currentWidth * 1.5));
      // Mikky in small, top left of the small window's head (ux-a.html).
      expect((m.mikkyX, m.mikkyY, m.mikkyRadius), (30, 39, 15));
      expect(m.cornerRadius, 38);
    });

    test('hides into the right edge', () {
      final m = IslandMotion(edge: IslandEdge.right)..setShape(IslandShape.compact);
      run(m, 2);
      m.setShape(IslandShape.hidden);
      run(m, 2);
      expect(m.isGone, isTrue);
      expect(m.currentWidth, 0);
      expect(m.visibility, 0);
    });
  });
}
