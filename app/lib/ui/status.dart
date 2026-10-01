import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'tokens.dart';

/// The look of an agent's state in the window (`.status`, « États d'un
/// agent »), from the island's [AgentStatus].
///
/// Only what tells the user something (user request, 2026-10-01: « garde
/// uniquement terminé, travaille, exclamation pour besoin de validation,
/// rate limite en jaune »): thinking and searching are working; paused
/// and idle show nothing.
enum UiStatus {
  working,
  approval,
  finished,
  error,
  limited,
  paused;

  static UiStatus of(AgentStatus s) => switch (s) {
    AgentStatus.working || AgentStatus.thinking || AgentStatus.searching => working,
    AgentStatus.approval || AgentStatus.question => approval,
    AgentStatus.finished => finished,
    AgentStatus.error => error,
    AgentStatus.rateLimited => limited,
    AgentStatus.idle || AgentStatus.paused => paused,
  };
}

/// The color of a state: blue working, amber waiting, red error…
Color statusColor(MikkyUi ui, UiStatus status) => switch (status) {
  UiStatus.working => ui.blue,
  UiStatus.approval => ui.amber,
  UiStatus.finished => ui.green,
  UiStatus.error => ui.red,
  UiStatus.limited => ui.yellow,
  UiStatus.paused => ui.grey,
};
