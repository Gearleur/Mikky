import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'tokens.dart';

/// The look of an agent's state in the window (`.status`, « États d'un
/// agent »), from the island's [AgentStatus].
enum UiStatus {
  working,
  thinking,
  approval,
  finished,
  error,
  limited,
  sleeping;

  static UiStatus of(AgentStatus s) => switch (s) {
    AgentStatus.working || AgentStatus.searching => working,
    AgentStatus.thinking => thinking,
    AgentStatus.approval || AgentStatus.question => approval,
    AgentStatus.finished => finished,
    AgentStatus.error => error,
    AgentStatus.rateLimited => limited,
    AgentStatus.idle || AgentStatus.paused => sleeping,
  };
}

/// The color of a state: blue working, purple thinking, amber waiting…
Color statusColor(MikkyUi ui, UiStatus status) => switch (status) {
  UiStatus.working => ui.blue,
  UiStatus.thinking => ui.purple,
  UiStatus.approval => ui.amber,
  UiStatus.finished => ui.green,
  UiStatus.error => ui.red,
  UiStatus.limited => ui.yellow,
  UiStatus.sleeping => ui.grey,
};
