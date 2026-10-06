import 'dart:math' as math;

import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Easings', () {
    for (final (name, e) in [('out', Easings.out), ('inOut', Easings.inOut), ('back', Easings.back)]) {
      test('$name goes from 0 to 1', () {
        expect(e(0), closeTo(0, 1e-9));
        expect(e(1), closeTo(1, 1e-9));
      });
    }

    test('back overshoots', () {
      expect(List.generate(100, (i) => Easings.back(i / 100)).any((v) => v > 1), isTrue);
    });
  });

  group('approach', () {
    test('is frame-rate independent', () {
      var at60 = 0.0, at144 = 0.0;
      for (var i = 0; i < 60; i++) {
        at60 = approach(at60, 1, .0025, 1 / 60);
      }
      for (var i = 0; i < 144; i++) {
        at144 = approach(at144, 1, .0025, 1 / 144);
      }
      expect(at60, closeTo(at144, 1e-9));
      expect(at60, closeTo(1 - .0025, 1e-9));
    });
  });

  group('Spring', () {
    test('settles on its target', () {
      final s = Spring(0, SpringSpec.island)..target = 100;
      for (var i = 0; i < 120; i++) {
        s.step(1 / 60);
      }
      expect(s.value, closeTo(100, .05));
      expect(s.isAtRest(.05), isTrue);
    });

    test('the sticky drop spring overshoots more than the dry island one', () {
      double peak(SpringSpec spec) {
        final s = Spring(0, spec)..target = 1;
        var max = 0.0;
        for (var i = 0; i < 180; i++) {
          s.step(1 / 60);
          if (s.value > max) max = s.value;
        }
        return max;
      }

      expect(peak(SpringSpec.drop), greaterThan(peak(SpringSpec.island)));
    });
  });

  group('KeyframeTrack', () {
    test('chains keyframes and keeps the leftover time', () {
      final track = KeyframeTrack(const [
        Keyframe(10, 100, Easings.linear),
        Keyframe(0, 100, Easings.linear),
      ], from: 0, start: 0);
      expect(track.sample(.05), closeTo(5, 1e-9));
      expect(track.sample(.15), closeTo(5, 1e-9));
      expect(track.isDone, isFalse);
      expect(track.sample(.25), 0);
      expect(track.isDone, isTrue);
    });
  });

  group('Easings.spring', () {
    test('ends on 1 and overshoots when soft', () {
      final e = Easings.spring(const SpringSpec(120, .42), .8);
      expect(e(0), closeTo(0, 1e-9));
      expect(e(1), closeTo(1, 1e-9));
      expect(List.generate(100, (i) => e(i / 100)).any((v) => v > 1), isTrue);
    });

    test('critically damped and overdamped never overshoot', () {
      for (final z in [1.0, 1.4]) {
        final e = Easings.spring(SpringSpec(100, z), 1.2);
        expect(List.generate(100, (i) => e(i / 100)).every((v) => v <= 1 + 1e-9), isTrue);
        expect(e(1), closeTo(1, 1e-9));
      }
    });
  });

  group('Choreography', () {
    final c = Choreography(
      name: 'essai',
      duration: 2,
      tracks: {
        'y': const [Beat(1, 10, Easings.linear), Beat(0, 0)],
      },
      marks: const [Mark(.5, 'pop'), Mark(1.5, 'end')],
    );

    test('holds before its first beat and after its last', () {
      expect(c.value('y', -1), 0);
      expect(c.value('y', 1.8), 10);
      expect(c.value('nope', .5, 3), 3);
    });

    test('goes from beat to beat along the ease', () {
      expect(c.value('y', .5), closeTo(5, 1e-9));
      expect(c.sample(.25)['y'], closeTo(2.5, 1e-9));
    });

    test('tells the marks passed between two frames, once', () {
      expect(c.passed(0, .5).map((m) => m.name), ['pop']);
      expect(c.passed(.5, 1), isEmpty);
      expect(c.at('end'), 1.5);
    });

    test('played slower, everything comes later', () {
      final slow = c.atSpeed(.8);
      expect(slow.duration, closeTo(2.5, 1e-9));
      expect(slow.value('y', 1.25), closeTo(10, 1e-9));
      expect(slow.value('y', .625), closeTo(5, 1e-9));
      expect(slow.at('pop'), closeTo(.625, 1e-9));
    });

    test('a wiggle ends on its rest value', () {
      final w = Choreography.wiggle(1, 2, .2, .5, 3);
      expect(w, hasLength(6));
      expect(w.last.at, closeTo(2, 1e-9));
      expect(w.last.value, .2);
    });
  });

  group('Burst', () {
    Burst make() => Burst(seed: 3, count: 20, speedMin: 50, speedMax: 100, sizeMin: 1, sizeMax: 2, lifeMin: .5, lifeMax: .8, drag: 2, gravity: 40);

    test('is the same every time', () {
      final a = make().at(.3).map((s) => s.x).toList(), b = make().at(.3).map((s) => s.x).toList();
      expect(a, b);
    });

    test('flies out, then is gone', () {
      final b = make();
      expect(b.at(.2), hasLength(20));
      expect(b.at(.2).every((s) => math.sqrt(s.x * s.x + s.y * s.y) > 1), isTrue);
      expect(b.at(.9), isEmpty);
    });
  });
}
