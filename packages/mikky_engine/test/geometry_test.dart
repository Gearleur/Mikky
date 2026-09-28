import 'dart:math' as math;

import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  test('the outline is closed and has the requested number of points', () {
    final g = MikkyGeometry.of(Mikky(random: math.Random(1)), 28);
    expect(g.pointCount, 361);
    expect(g.contour[0], closeTo(g.contour[720], 1e-9));
    expect(g.contour[1], closeTo(g.contour[721], 1e-9));
    expect(g.fur, isEmpty);
    expect(MikkyGeometry.of(Mikky(), 9, points: 180).pointCount, 181);
  });

  test('at rest, the silhouette is symmetric, with ears above the head', () {
    final g = MikkyGeometry.of(Mikky(random: math.Random(1)), 100);
    var minX = 0.0, maxX = 0.0, minY = 0.0;
    for (var i = 0; i < g.pointCount; i++) {
      final x = g.contour[i * 2], y = g.contour[i * 2 + 1];
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
    }
    expect(minX, closeTo(-maxX, .5));
    // Head top at -0.92 R; ears add up to 0.55 R.
    expect(minY, lessThan(-92 - 40));
    expect(minY, greaterThan(-92 - 60));
  });

  test('two eyes, symmetric, above the center, no pupil', () {
    final g = MikkyGeometry.of(Mikky(random: math.Random(1)), 100);
    expect(g.eyes, hasLength(2));
    expect(g.eyes[0].x, closeTo(-g.eyes[1].x, 1e-9));
    expect(g.eyes[0].y, lessThan(0));
    expect(g.eyes[0].width, closeTo(21, 1e-9));
    expect(g.eyes[0].height, closeTo(62.5, 1e-9));
  });

  test('an eye turned far away hides behind the head', () {
    final m = Mikky(random: math.Random(1));
    m.pose[MikkyProp.yaw] = 1.4;
    expect(MikkyGeometry.of(m, 100).eyes, hasLength(1));
  });

  test('closed eyelids keep a thin slit', () {
    final m = Mikky(random: math.Random(1));
    m.pose[MikkyProp.open] = 0;
    final eye = MikkyGeometry.of(m, 100).eyes.first;
    expect(eye.height, closeTo(eye.width * .25, 1e-9));
  });
}
