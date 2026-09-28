/// Time source of the engine, in seconds. Injected so that tests control
/// time instead of waiting.
abstract interface class Clock {
  double get now;
}

/// Monotonic time since the clock was created.
class SystemClock implements Clock {
  final _watch = Stopwatch()..start();

  @override
  double get now => _watch.elapsedMicroseconds / 1e6;
}

/// Time that only moves when told to.
class FakeClock implements Clock {
  FakeClock([this.now = 0]);

  @override
  double now;

  void advance(double seconds) => now += seconds;
}
