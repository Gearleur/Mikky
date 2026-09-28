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
}
