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
    expect(m.eyeLeft, EyeShape.happy);
    expect(m.pose.earLeft, greaterThan(.1));
    run(m, 3);
    expect(m.eyeLeft, EyeShape.oval);
    expect(m.pose.earLeft, closeTo(0, .02));
  });

  group('states (spec §5.2 table)', () {
    MikkyGeometry settle(MikkyState s) {
      final m = Mikky(random: math.Random(2))..setState(s);
      run(m, 2.5);
      return MikkyGeometry.of(m, 100);
    }

    test('approval: big eyes, and he turns into the "!" himself, no badge', () {
      final m = Mikky(random: math.Random(2))..setState(MikkyState.approval);
      run(m, 2);
      expect(m.pose.eyeScale, greaterThan(1.1));
      expect(m.form, MikkyForm.bang);
      expect(m.morph, closeTo(1, .05));
      expect(m.badge, isNull);
      expect(MikkyGeometry.of(m, 100).satellites, hasLength(1));
    });

    test('question: one ear folded, head tilted, "?" badge', () {
      final m = Mikky(random: math.Random(2))..setState(MikkyState.question);
      run(m, 3);
      expect(m.pose[MikkyProp.earBaseLeft], lessThan(-.5));
      expect(m.pose[MikkyProp.earBaseRight], greaterThan(0));
      expect(m.pose[MikkyProp.tilt], greaterThan(.1));
      expect(m.badge?.kind, BadgeKind.question);
    });

    test('error: flat eyes, ears down, a shake when it starts', () {
      final m = Mikky(random: math.Random(2))..setState(MikkyState.error);
      run(m, .1);
      expect(m.pose.offsetX.abs(), greaterThan(0));
      expect(settle(MikkyState.error).eyes.every((e) => e.shape == EyeShape.flat), isTrue);
      expect(m.badge?.color, AgentStatus.error);
    });

    test('finished: happy arcs, a roll and sparkles', () {
      final m = Mikky(random: math.Random(2))..setState(MikkyState.finished);
      run(m, .3);
      expect(m.pose.tilt.abs(), greaterThan(.5));
      expect(m.particles.where((p) => p.kind == ParticleKind.sparkle), isNotEmpty);
      run(m, 2);
      expect(m.pose[MikkyProp.spin], 0);
      expect(m.eyeLeft, EyeShape.happy);
    });

    test('sleeping: closed eyes, droopy ears, "z", no blinking', () {
      final m = Mikky(random: math.Random(2))..setState(MikkyState.sleeping);
      var sawZ = false;
      for (var i = 0; i < 60 * 8; i++) {
        m.update(1 / 60);
        expect(m.pose.open, 1);
        if (m.particles.any((p) => p.kind == ParticleKind.sleep)) sawZ = true;
      }
      expect(sawZ, isTrue);
      expect(m.eyeLeft, EyeShape.closed);
      expect(m.pose[MikkyProp.earBaseLeft], lessThan(-.4));
    });

    test('rate limited: tired eyes and sweat drops', () {
      final m = Mikky(random: math.Random(2))..setState(MikkyState.rateLimited);
      run(m, 2);
      expect(m.eyeLeft, EyeShape.tired);
      expect(m.particles.where((p) => p.kind == ParticleKind.sweat), isNotEmpty);
    });

    test('thinking looks up and to the right, whatever the cursor', () {
      final m = Mikky(random: math.Random(2))..setState(MikkyState.thinking);
      run(m, 3, lookX: -1, lookY: 1);
      expect(m.pose.yaw, greaterThan(.2));
      expect(m.pose.pitch, greaterThan(.2));
      // Unless the app asks for attention (the split bubble).
      for (var i = 0; i < 180; i++) {
        m.update(1 / 60, lookX: -1, attention: true);
      }
      expect(m.pose.yaw, lessThan(-.3));
    });

    test('every state has its eyes', () {
      for (final s in MikkyState.values) {
        final g = settle(s);
        expect(g.eyes, isNotEmpty, reason: '$s');
      }
    });
  });

  group('forms: Mikky turns into the sign', () {
    test('working: a fur ball; thinking: the middle dot of three', () {
      final m = Mikky(random: math.Random(5))..setState(MikkyState.working);
      run(m, 2);
      expect((m.form, m.badge), (MikkyForm.furball, null));
      m.setState(MikkyState.thinking);
      run(m, 3);
      expect(m.form, MikkyForm.dots);
      final g = MikkyGeometry.of(m, 100);
      expect(g.satellites, hasLength(2));
      // The two other dots sit on each side of him.
      double centerX(List<double> c) {
        var sum = 0.0;
        for (var i = 0; i < c.length; i += 2) {
          sum += c[i];
        }
        return sum / (c.length / 2);
      }

      expect(centerX(g.satellites[0]), lessThan(-100));
      expect(centerX(g.satellites[1]), greaterThan(100));
    });

    test('from one form to another, he goes back through the cat', () {
      final m = Mikky(random: math.Random(5))..setState(MikkyState.working);
      run(m, 2);
      m.setState(MikkyState.approval);
      var sawCat = false;
      for (var i = 0; i < 180; i++) {
        m.update(1 / 60);
        if (m.morph.abs() < .1) sawCat = true;
      }
      expect(sawCat, isTrue);
      expect(m.form, MikkyForm.bang);
    });

    test('the change is soft: it overshoots, then settles', () {
      final m = Mikky(random: math.Random(5))..play(MikkyEmote.love);
      var peak = 0.0;
      for (var i = 0; i < 60; i++) {
        m.update(1 / 60);
        peak = math.max(peak, m.morph);
      }
      expect(m.form, MikkyForm.heart);
      expect(peak, greaterThan(1.05));
    });

    test('back to the cat when the state has no form', () {
      final m = Mikky(random: math.Random(5))..setState(MikkyState.working);
      run(m, 2);
      m.setState(MikkyState.error);
      run(m, 3);
      expect(m.morph.abs(), lessThan(.01));
      expect(MikkyGeometry.of(m, 100).satellites, isEmpty);
      expect(m.badge?.color, AgentStatus.error);
    });

    test('every form keeps a closed outline and two eyes', () {
      for (final s in [MikkyState.working, MikkyState.thinking, MikkyState.approval]) {
        final m = Mikky(random: math.Random(5))..setState(s);
        run(m, 2);
        final g = MikkyGeometry.of(m, 100);
        expect(g.contour[0], closeTo(g.contour[g.contour.length - 2], 1e-6), reason: '$s');
        expect(g.eyes, hasLength(2), reason: '$s');
      }
    });
  });

  group('emotes', () {
    test('each emote changes the look, then fades', () {
      for (final e in MikkyEmote.values) {
        final m = Mikky(random: math.Random(3))..play(e);
        run(m, .2);
        expect(m.emote, e);
        run(m, 2);
        expect(m.emote, isNull, reason: '$e');
      }
    });

    test('love: he becomes the heart, content eyes, hearts; proud shows stars; wink closes one eye', () {
      final love = Mikky(random: math.Random(3))..play(MikkyEmote.love);
      run(love, .7);
      expect(love.form, MikkyForm.heart);
      expect(love.eyeLeft, EyeShape.happy);
      expect(love.particles.where((p) => p.kind == ParticleKind.heart), isNotEmpty);

      final proud = Mikky(random: math.Random(3))..play(MikkyEmote.proud);
      run(proud, .2);
      expect(proud.particles.where((p) => p.kind == ParticleKind.star), hasLength(6));

      final wink = Mikky(random: math.Random(3))..play(MikkyEmote.wink);
      run(wink, .1);
      expect((wink.eyeLeft, wink.eyeRight), (EyeShape.oval, EyeShape.happy));
    });
  });

  group('interactions', () {
    test('hover blinks and widens the eyes; still for 1.9 s, love', () {
      final m = Mikky(random: math.Random(4));
      m.hover(true);
      run(m, .07);
      expect(m.pose.open, lessThan(.2));
      run(m, 1.5);
      expect(m.pose.eyeScale, closeTo(1.08, .02));
      expect(m.emote, isNull);
      run(m, .5);
      expect(m.emote, MikkyEmote.love);
    });

    test('moving the cursor delays the love', () {
      final m = Mikky(random: math.Random(4))..hover(true);
      for (var i = 0; i < 4; i++) {
        run(m, 1);
        m.pointerMoved();
      }
      expect(m.emote, isNull);
    });

    test('three clicks within 1.7 s: dizzy for a moment', () {
      final m = Mikky(random: math.Random(4))..setState(MikkyState.working);
      m.boop();
      run(m, .4);
      m.boop();
      run(m, .4);
      expect(m.state, MikkyState.working);
      m.boop();
      run(m, .1);
      expect(m.state, MikkyState.dizzy);
      expect(m.eyeLeft, EyeShape.spiral);
      run(m, 3);
      expect(m.state, MikkyState.working);
    });
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
