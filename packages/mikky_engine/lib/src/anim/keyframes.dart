import 'easing.dart';

/// Go to [target] in [durationMs] milliseconds with [easing].
class Keyframe {
  const Keyframe(this.target, this.durationMs, [this.easing = Easings.inOut]);

  final double target;
  final double durationMs;
  final Easing easing;
}

/// A sequence of keyframes played from [from], starting at time [start]
/// (seconds). Each keyframe starts from the previous target.
class KeyframeTrack {
  KeyframeTrack(this.keys, {required this._from, required this._start}) : assert(keys.isNotEmpty);

  final List<Keyframe> keys;
  double _from;
  double _start;
  int _index = 0;

  bool get isDone => _index >= keys.length;

  /// Value at [time] (seconds). Once done, returns the last target.
  double sample(double time) {
    while (_index < keys.length) {
      final key = keys[_index];
      final duration = key.durationMs / 1000;
      final q = duration <= 0 ? 1.0 : (time - _start) / duration;
      if (q < 1) {
        final eased = key.easing(q < 0 ? 0 : q);
        return _from + (key.target - _from) * eased;
      }
      // Keep the leftover time for the next keyframe.
      _from = key.target;
      _start += duration;
      _index++;
    }
    return _from;
  }
}
