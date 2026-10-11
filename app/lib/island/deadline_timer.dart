import 'dart:async';
import 'dart:math' as math;

/// One timer for the nearest of several deadlines (clock seconds): the
/// island sleeps until then, nothing runs meanwhile.
class DeadlineTimer {
  DeadlineTimer(this._onDeadline);

  final void Function() _onDeadline;
  Timer? _timer;
  double? _at;

  /// Sets the timer for the nearest of [deadlines] (null ones ignored);
  /// none: no timer. A later deadline can wait: the timer already set
  /// fires first and the caller schedules again.
  void schedule(Iterable<double?> deadlines, {required double now}) {
    double? next;
    for (final t in deadlines) {
      if (t != null && (next == null || t < next)) next = t;
    }
    if (next == null) return cancel();
    final at = _at;
    if (at != null && at <= next && (_timer?.isActive ?? false)) return;
    _timer?.cancel();
    _at = next;
    // 2 ms late, so the deadline has passed when it fires.
    final delay = math.max(0, ((next - now) * 1e6).ceil()) + 2000;
    _timer = Timer(Duration(microseconds: delay), () {
      _at = null;
      _onDeadline();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _at = null;
  }
}
