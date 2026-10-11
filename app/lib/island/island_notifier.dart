import 'package:mikky_engine/mikky_engine.dart';

/// Windows notifications for the agents: when a real agent starts waiting
/// for the user, fails or finishes. Once per agent and state.
class IslandNotifier {
  IslandNotifier(this._show);

  /// Shows one notification (title, body).
  final void Function(String title, String body) _show;

  /// The state each agent was last notified in.
  final Map<String, AgentStatus> _notified = {};

  /// The agent of the last notification (a click on it opens its page).
  String? get lastAgent => _lastAgent;
  String? _lastAgent;

  /// Notifies what changed in [agents]. Nothing shows when [enabled] is
  /// off; nothing either while [windowOpen] (the user is looking at it),
  /// though the state is still remembered.
  void update(List<Agent> agents, {required bool enabled, required bool windowOpen}) {
    final ids = {for (final a in agents) a.id};
    _notified.removeWhere((id, _) => !ids.contains(id));
    if (!enabled) return;
    for (final a in agents) {
      final body = bodyOf(a);
      if (body == null) {
        _notified.remove(a.id);
        continue;
      }
      if (_notified[a.id] == a.status) continue;
      _notified[a.id] = a.status;
      if (windowOpen) continue;
      _lastAgent = a.id;
      _show(a.name, body);
    }
  }

  /// The notification's text for [agent], null when its state needs none.
  static String? bodyOf(Agent agent) {
    final detail = agent.detail.isEmpty ? '' : ' : ${agent.detail}';
    return switch (agent.status) {
      AgentStatus.approval => 'Attend ton feu vert$detail',
      AgentStatus.question => 'Te pose une question$detail',
      AgentStatus.error => 'Erreur$detail',
      AgentStatus.finished => 'Terminé$detail',
      _ => null,
    };
  }
}
