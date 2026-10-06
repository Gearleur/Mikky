import 'dart:math' as math;

import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  test('the outline is closed and has the requested number of points', () {
    final g = MikkyGeometry.of(Mikky(random: math.Random(1)), 28);
    expect(g.pointCount, 361);
    expect(g.contour[0], closeTo(g.contour[720], 1e-9));
    expect(g.contour[1], closeTo(g.contour[721], 1e-9));
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

  test('his arms are out of sight until the pose brings them out', () {
    final pose = MikkyPose();
    double widest(MikkyGeometry g) => [for (var i = 0; i < g.contour.length; i += 2) g.contour[i].abs()].reduce(math.max);
    final still = MikkyGeometry.posed(pose, 40);
    pose[MikkyProp.arms] = 1;
    // Each style pushes his outline out somewhere, by a few pixels.
    for (final style in ArmStyle.values) {
      final g = MikkyGeometry.posed(pose, 40, arms: style);
      var most = 0.0;
      for (var i = 0; i < g.contour.length; i += 2) {
        most = math.max(most, math.sqrt(math.pow(g.contour[i] - still.contour[i], 2) + math.pow(g.contour[i + 1] - still.contour[i + 1], 2)));
      }
      expect(most, greaterThan(7), reason: '$style');
    }
    expect(widest(MikkyGeometry.posed(pose, 40)), greaterThan(widest(still) + 5));
    // Raised, the right arm turns up from where it grows: its outline
    // goes up, on the right only.
    final rest = MikkyGeometry.posed(pose, 40);
    pose[MikkyProp.armRightLift] = 1.2;
    final up = MikkyGeometry.posed(pose, 40);
    var rightUp = 0.0, leftMoved = 0.0;
    for (var i = 0; i < up.contour.length; i += 2) {
      final dy = up.contour[i + 1] - rest.contour[i + 1];
      if (rest.contour[i] > 0) rightUp += dy;
      if (rest.contour[i] < 0) leftMoved += dy.abs();
    }
    expect(rightUp, lessThan(-50));
    expect(leftMoved, closeTo(0, 1e-6));
  });
}
