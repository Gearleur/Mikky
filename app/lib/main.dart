import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'agents/agents_service.dart';

import 'island/island_painter.dart';
import 'island/island_view.dart';
import 'overlay/overlay_channel.dart';
import 'settings.dart';
import 'boards/boards_app.dart';
import 'tuning/tuning_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final tuning = await Settings.loadTuning();

  // The design boards (brand, components, every screen): a normal window,
  // in its own process.
  if (args.contains('--kit')) {
    runApp(BoardsApp(performance: args.contains('--perf')));
    return;
  }

  // The tuning screen: a normal window, in its own process.
  if (args.contains('--tuning')) {
    runApp(TuningApp(tuning: tuning));
    return;
  }

  final overlay = OverlayChannel();
  final clock = SystemClock();
  // Claude and Codex: found and followed in the background, never blocking
  // the island's first frame.
  final agents = AgentsService(clock: () => clock.now);
  unawaited(agents.start());
  final (settings, program) = await (Settings.load(), loadIslandProgram()).wait;
  // Before the first frame: the window only shows up once it is in place.
  await overlay.setPlacement(settings.edge, windowSizeFor(settings.edge));
  // A bare WidgetsApp: no background (everything outside the island must
  // stay fully transparent), but the text shortcuts (Ctrl+C, Ctrl+V…) and an
  // Overlay for the « Copier » menu of the small window.
  runApp(WidgetsApp(
    title: 'Mikky',
    color: const Color(0x00000000),
    debugShowCheckedModeBanner: false,
    builder: (context, _) => Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => IslandView(overlay: overlay, settings: settings, program: program, tuning: tuning, clock: clock, agents: agents),
        ),
      ],
    ),
  ));
}
