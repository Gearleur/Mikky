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

    test('the list layout is the home: taller, Mikky at its top left', () {
      final m = IslandMotion()..setShape(IslandShape.open, layout: IslandLayout.list);
      run(m, 2);
      expect(m.currentWidth, 450);
      expect(m.currentHeight, 260);
      expect((m.mikkyX, m.mikkyY, m.mikkyRadius), (40, 35, 21));
      // An alert: the same island takes the focus size, Mikky its place.
      m.setShape(IslandShape.open, layout: IslandLayout.focus);
      run(m, 2);
      expect((m.currentWidth, m.currentHeight), (430, 178));
      expect(m.mikkyRadius, 28);
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
      expect((m.currentWidth, m.currentHeight), (74, 82));
      expect(m.visibility, 1);
      expect(m.mikkyRadius, 15);
    });

    test('open is a portrait card, taller than wide', () {
      final m = IslandMotion(edge: IslandEdge.right)..setShape(IslandShape.compact);
      run(m, 2);
      m.setShape(IslandShape.open);
      run(m, 2 / 60);
      // The depth (width, away from the edge) waits for the length.
      expect(m.currentHeight, greaterThan(82));
      expect(m.currentWidth, 74);
      run(m, 2);
      expect((m.currentWidth, m.currentHeight), (344, 520));
      expect(m.currentHeight, greaterThan(m.currentWidth * 1.5));
      // Mikky at the top left of the home (2026-10-02).
      expect((m.mikkyX, m.mikkyY, m.mikkyRadius), (40, 37, 21));
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
