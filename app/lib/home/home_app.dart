import 'package:mikky_engine/mikky_engine.dart';

import '../ui/brand/brand_logo.dart';
import '../ui/foundation/status.dart';

/// One app of the home: one or more agents doing a task (user, 2026-10-02).
/// For now one agent. At the right its tile shows its tool and its state;
/// in the notch its title, [line] and the software it runs in ([app]).
class HomeApp {
  const HomeApp({required this.id, this.name = '', this.brand, this.status, this.line = '', this.app});

  final String id;
  final String name;

  /// The tool it runs with; null: a neutral tile (the boards).
  final Brand? brand;

  /// Its state, in a pastille on the corner; null: nothing.
  final UiStatus? status;

  /// What it does now, or how it ended, in a few words (the notch).
  final String line;

  /// The software it runs in (the notch), if known.
  final AgentApp? app;

  /// [n] neutral apps, for the boards.
  static List<HomeApp> placeholders(int n) => [
    for (var i = 0; i < n; i++) HomeApp(id: 'app-$i', name: 'Application ${i + 1}'),
  ];
}
