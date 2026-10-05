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
      expect(m.currentWidth, 760);
      expect(m.currentHeight, 260);
      expect(m.cornerRadius, 30);
      expect(m.mikkyRadius, 28);
      expect(m.openContentOpacity, 1);
    });

    test('the list layout is the home: the notch, Mikky big on its left', () {
      final m = IslandMotion()..setShape(IslandShape.open, layout: IslandLayout.list);
      run(m, 2);
      expect(m.currentWidth, 760);
      expect(m.currentHeight, 216);
      expect((m.mikkyX, m.mikkyY, m.mikkyRadius), (62, 118, 29));
      // Nothing at work: Mikky goes to his bigger place, on a spring.
      m.listIdle = true;
      run(m, 2);
      expect((m.mikkyX, m.mikkyY, m.mikkyRadius), (83, 121.12, 37.12));
      // An alert: the request Mikky brings, as big as the home (2026-10-04),
      // Mikky at his focus place.
      m.setShape(IslandShape.open, layout: IslandLayout.focus);
      run(m, 2);
      expect((m.currentWidth, m.currentHeight), (760, 260));
      expect(m.mikkyRadius, 28);
    });

    test('a page over the home: its own size, Mikky behind the back button', () {
      final m = IslandMotion()..setShape(IslandShape.open, layout: IslandLayout.list);
      run(m, 2);
      m.setShape(IslandShape.open, layout: IslandLayout.page);
      run(m, 2);
      expect((m.currentWidth, m.currentHeight), (760, 380));
      expect((m.mikkyX, m.mikkyY, m.mikkyRadius), (40, 35, 21));
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
      m.setShape(IslandShape.open, layout: IslandLayout.page);
      run(m, 2 / 60);
      // The depth (width, away from the edge) waits for the length.
      expect(m.currentHeight, greaterThan(82));
      expect(m.currentWidth, 74);
      run(m, 2);
      expect((m.currentWidth, m.currentHeight), (344, 520));
      expect(m.currentHeight, greaterThan(m.currentWidth * 1.4));
      expect((m.mikkyX, m.mikkyY, m.mikkyRadius), (40, 35, 21));
      expect(m.cornerRadius, 30);
    });

    test('the home at the right is the top one, upright', () {
      final m = IslandMotion(edge: IslandEdge.right)..setShape(IslandShape.open, layout: IslandLayout.list);
      run(m, 2);
      expect((m.currentWidth, m.currentHeight), (290, 408));
      expect((m.mikkyX, m.mikkyY, m.mikkyRadius), (40, 35, 21));
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
