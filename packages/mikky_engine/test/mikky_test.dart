import 'dart:math' as math;

import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void run(Mikky m, double seconds, {double lookX = 0, double lookY = 0}) {
  final frames = (seconds * 60).round();
  for (var i = 0; i < frames; i++) {
    m.update(1 / 60, lookX: lookX, lookY: lookY);
  }
}

void main() {
  test('a blink closes then reopens the eyes', () {
    final m = Mikky(random: math.Random(1));
    m.blink();
    run(m, .07);
    expect(m.pose.open, lessThan(.1));
    run(m, .15);
    expect(m.pose.open, closeTo(1, 1e-9));
  });

  test('blinks on its own every 2.2 to 5.4 s', () {
    final m = Mikky(random: math.Random(7));
    final closedAt = <double>[];
    var wasClosed = false;
    for (var i = 0; i < 60 * 30; i++) {
      m.update(1 / 60);
      final closed = m.pose.open < .5;
      if (closed && !wasClosed) closedAt.add(m.time);
      wasClosed = closed;
    }
    expect(closedAt.first, lessThan(3.2));
    // Blinks, possibly doubled (230 ms apart): never more than 5.4 s without one.
    for (var i = 1; i < closedAt.length; i++) {
      expect(closedAt[i] - closedAt[i - 1], lessThan(5.5));
    }
    expect(closedAt.length, greaterThanOrEqualTo(30 ~/ 5.4));
  });

  test('turns its head toward the gaze and tilts that way', () {
    final m = Mikky(random: math.Random(1));
    run(m, 2, lookX: 1);
    expect(m.pose.yaw, closeTo(.5, .01));
    expect(m.pose.tilt, greaterThan(0));
    run(m, 2, lookX: -1, lookY: 1);
    expect(m.pose.yaw, closeTo(-.5, .01));
    expect(m.pose.pitch, closeTo(-.32, .01));
  });

  test('lookAt saturates far away', () {
    expect(Mikky.lookAt(0, 0), (0.0, 0.0));
    final (x, y) = Mikky.lookAt(5000, -5000);
    expect(x, closeTo(1, 1e-6));
    expect(y, closeTo(-1, 1e-6));
  });

  test('breathing stays subtle', () {
    final m = Mikky(random: math.Random(3));
    for (var i = 0; i < 600; i++) {
      m.update(1 / 60);
      expect(m.pose.scaleY, inInclusiveRange(.97, 1.03));
    }
  });

  test('happy shows arcs, then goes back to ovals', () {
    final m = Mikky(random: math.Random(1));
    m.happy();
    run(m, .5);
    expect(m.eyes, EyeShape.happy);
    run(m, 1.5);
    expect(m.eyes, EyeShape.oval);
    expect(m.pose.earLeft, closeTo(0, 1e-9));
  });

  test('twitch without side moves both ears, the right one later', () {
    final m = Mikky(random: math.Random(1));
    m.twitch();
    run(m, .05);
    expect(m.pose.earLeft, greaterThan(0));
    expect(m.pose.earRight, 0);
    run(m, .1);
    expect(m.pose.earRight, greaterThan(0));
  });
}
