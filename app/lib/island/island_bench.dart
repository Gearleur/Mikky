import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

/// `--bench` (development): the island with one made-up agent at work, to
/// measure its CPU in a steady state; `--fast` keeps 60 frames a second as
/// the island did before it rested on the decor clock.
enum IslandBench {
  calm,
  fast;

  /// Counts the frames from 4 s to 16 s, appends them with [describe]'s
  /// line to `%TEMP%\mikky-bench.txt`, then calls [done].
  void run({required String Function() describe, required void Function() done}) {
    final timings = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> t) => timings.addAll(t);
    Timer(const Duration(seconds: 4), () {
      SchedulerBinding.instance.addTimingsCallback(collect);
      Timer(const Duration(seconds: 12), () {
        SchedulerBinding.instance.removeTimingsCallback(collect);
        double avg(Duration Function(ui.FrameTiming) f) => timings.isEmpty
            ? 0
            : timings.map((t) => f(t).inMicroseconds).reduce((a, b) => a + b) / timings.length / 1000;
        final line =
            '$name: ${(timings.length / 12).toStringAsFixed(1)} frames/s, '
            'build ${avg((t) => t.buildDuration).toStringAsFixed(2)} ms, '
            'raster ${avg((t) => t.rasterDuration).toStringAsFixed(2)} ms, ${describe()}';
        File('${Platform.environment['TEMP']}/mikky-bench.txt').writeAsStringSync('$line\n', mode: FileMode.append);
        done();
      });
    });
  }
}
