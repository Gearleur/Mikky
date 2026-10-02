import 'package:mikky_engine/mikky_engine.dart';

/// A button of the agent in focus, and the answer it sends.
class FocusAction {
  const FocusAction(this.label, this.answer, {this.primary = false, this.keyHint});

  final String label;
  final AgentAnswer answer;
  final bool primary;

  /// Keyboard shortcut shown on the dark theme (N / Y).
  final String? keyHint;
}

/// What the open island says about one agent, in French.
class AgentText {
  const AgentText({
    required this.agent,
    required this.verb,
    required this.detail,
    required this.detailIsError,
    required this.when,
    required this.progress,
    required this.actions,
  });

  factory AgentText.of(Agent a, double now) {
    final elapsed = _duration(now - a.startedAt);
    final progress = a.progressAt(now);
    final (verb, actions) = switch (a.status) {
      AgentStatus.working => ('travaille', const <FocusAction>[]),
      AgentStatus.thinking => ('réfléchit', const <FocusAction>[]),
      AgentStatus.searching => ('cherche', const <FocusAction>[]),
      AgentStatus.approval => (
          'veut lancer',
          const [
            FocusAction('Refuser', AgentAnswer.deny, keyHint: 'N'),
            FocusAction('Autoriser', AgentAnswer.allow, primary: true, keyHint: 'Y'),
          ],
        ),
      AgentStatus.question => (
          'a une question',
          const [
            FocusAction('Plus tard', AgentAnswer.dismiss),
            FocusAction('Ouvrir le terminal', AgentAnswer.dismiss, primary: true),
          ],
        ),
      AgentStatus.error => (
          'a échoué',
          const [
            FocusAction('Ignorer', AgentAnswer.dismiss),
            FocusAction('Relancer', AgentAnswer.retry, primary: true),
          ],
        ),
      AgentStatus.finished => ('a terminé', const [FocusAction('OK', AgentAnswer.dismiss, primary: true)]),
      AgentStatus.rateLimited => ('est limité', const <FocusAction>[]),
      AgentStatus.paused => ('est en pause', const <FocusAction>[]),
      AgentStatus.idle => ('attend', const <FocusAction>[]),
    };
    return AgentText(
      agent: a,
      verb: verb,
      detail: a.detail,
      detailIsError: a.status == AgentStatus.error,
      when: a.status.needsYou || a.status == AgentStatus.finished ? 'maintenant' : elapsed,
      progress: a.status.isBusy ? progress : null,
      actions: actions,
    );
  }

  final Agent agent;
  final String verb;
  final String detail;
  final bool detailIsError;

  /// "maintenant" for what needs you, else the time since it started.
  final String when;
  final double? progress;
  final List<FocusAction> actions;

  /// Short line for the agent list.
  String get listActivity => agent.status == AgentStatus.approval ? 'attend ton feu vert' : detail;

  /// Short time for the agent list.
  String get listTime => agent.status.needsYou || agent.status == AgentStatus.finished ? 'maint.' : when;
}

/// Everything the open island shows, for one snapshot.
class IslandText {
  IslandText._({required this.content, required this.focus, required this.others, required this.all, required this.header});

  factory IslandText.of(IslandSnapshot s, double now) {
    final all = [for (final a in s.agents) AgentText.of(a, now)];
    final focus = s.focus == null ? null : AgentText.of(s.focus!, now);
    return IslandText._(
      content: s.content,
      focus: focus,
      others: [
        for (final t in all)
          if (t.agent.id != focus?.agent.id) t,
      ],
      all: all,
      header: _header(s),
    );
  }

  /// [agent] in focus, picked on the home's tiles at the top (2026-10-02).
  factory IslandText.agent(Agent agent, IslandSnapshot s, double now) {
    final all = [for (final a in s.agents) AgentText.of(a, now)];
    return IslandText._(
      content: IslandContent.focus,
      focus: AgentText.of(agent, now),
      others: [
        for (final t in all)
          if (t.agent.id != agent.id) t,
      ],
      all: all,
      header: _header(s),
    );
  }

  final IslandContent content;
  final AgentText? focus;

  /// Every agent but the one in focus.
  final List<AgentText> others;
  final List<AgentText> all;

  /// One sentence about the whole situation (portrait layout).
  final String header;

  static String _header(IslandSnapshot s) {
    final n = s.agents.length;
    final waiting = s.pendingAlerts;
    if (n == 0) return 'Aucun agent pour l\'instant';
    if (waiting == 1) return '1 agent attend ton feu vert';
    if (waiting > 1) return '$waiting agents attendent ton feu vert';
    final busy = s.agents.where((a) => a.status.isBusy).length;
    if (busy == 0) return n == 1 ? '1 agent' : '$n agents';
    return busy == 1 ? '1 agent au travail' : '$busy agents au travail';
  }
}

String _duration(double seconds) {
  final s = seconds < 0 ? 0 : seconds.floor();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
