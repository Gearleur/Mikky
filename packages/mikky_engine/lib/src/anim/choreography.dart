import 'easing.dart';

/// One value at one instant of a [Choreography]: coming from the beat
/// before, the value reaches [value] at [at] seconds, along [ease].
class Beat {
  const Beat(this.at, this.value, [this.ease = Easings.inOut]);

  final double at, value;
  final Easing ease;
}

/// A named instant of a [Choreography]: a sound, particles, a moment to
/// look at.
class Mark {
  const Mark(this.at, this.name);

  final double at;
  final String name;
}

/// A whole animation written by hand, as one function of time (like the
/// greeting of Coucou's Mochi): named tracks of [Beat]s on the same time
/// line, and [Mark]s. Nothing runs by itself: anyone can show any instant,
/// play it slowly, or go back.
class Choreography {
  Choreography({required this.name, required this.duration, required Map<String, List<Beat>> tracks, this.marks = const []})
      : tracks = {
          for (final e in tracks.entries) e.key: List.unmodifiable(List.of(e.value)..sort((a, b) => a.at.compareTo(b.at))),
        };

  final String name;

  /// Seconds.
  final double duration;
  final Map<String, List<Beat>> tracks;
  final List<Mark> marks;

  /// The value of [track] at [t] seconds; [fallback] if it has no beats.
  /// Before its first beat, that beat's value; after its last, the last.
  double value(String track, double t, [double fallback = 0]) {
    final beats = tracks[track];
    if (beats == null || beats.isEmpty) return fallback;
    if (t <= beats.first.at) return beats.first.value;
    for (var i = 1; i < beats.length; i++) {
      final b = beats[i];
      if (t < b.at) {
        final a = beats[i - 1];
        return a.value + (b.value - a.value) * b.ease((t - a.at) / (b.at - a.at));
      }
    }
    return beats.last.value;
  }

  /// Every track at [t].
  Map<String, double> sample(double t) => {for (final name in tracks.keys) name: value(name, t)};

  /// The marks passed going from [from] to [to] (a frame and the next):
  /// after [from], up to [to] included.
  Iterable<Mark> passed(double from, double to) => marks.where((m) => m.at > from && m.at <= to);

  /// The same, played at [speed] (0.8: slower, every moment a quarter
  /// later): its beats, marks and length stretched in time.
  Choreography atSpeed(double speed) => Choreography(
        name: name,
        duration: duration / speed,
        tracks: {
          for (final e in tracks.entries) e.key: [for (final b in e.value) Beat(b.at / speed, b.value, b.ease)],
        },
        marks: [for (final m in marks) Mark(m.at / speed, m.name)],
      );

  /// When the mark [name] is, or null.
  double? at(String name) {
    for (final m in marks) {
      if (m.name == name) return m.at;
    }
    return null;
  }

  /// Back and forth around [rest], [count] times between [from] and [to]
  /// seconds, [amount] each way, the last ones smaller; ends on [rest].
  static List<Beat> wiggle(double from, double to, double rest, double amount, int count) {
    final step = (to - from) / (count * 2);
    return [
      for (var i = 0; i < count * 2; i++)
        Beat(
          from + step * (i + 1),
          i == count * 2 - 1 ? rest : rest + (i.isEven ? amount : -amount) * (1 - i / (count * 2)),
          Easings.inOut,
        ),
    ];
  }
}
