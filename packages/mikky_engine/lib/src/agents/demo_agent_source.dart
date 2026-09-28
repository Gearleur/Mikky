import 'dart:math' as math;

import 'agent.dart';
import 'agent_source.dart';

/// Fake agents for the demo mode (spec §5.5). The scenario plays by itself:
/// three agents at work, an approval, an error, a finished agent. Answers
/// change what happens next.
class DemoAgentSource implements AgentSource {
  DemoAgentSource({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  final List<Agent> _agents = [];
  final List<(double, void Function(double))> _events = [];
  final Map<String, Map<AgentAnswer, void Function(double)>> _answers = {};
  int _added = 0;

  /// A finished agent stays this long in the list (the island shows it 5.2 s).
  static const finishedLinger = 8.0;

  @override
  List<Agent> get agents => List.unmodifiable(_agents);

  @override
  double? get nextDeadline => _events.isEmpty ? null : _events.first.$1;

  @override
  bool advance(double now) {
    var changed = false;
    while (_events.isNotEmpty && _events.first.$1 <= now) {
      final (at, run) = _events.removeAt(0);
      run(at);
      changed = true;
    }
    return changed;
  }

  @override
  bool answer(String id, AgentAnswer answer, double now) {
    final handlers = _answers[id];
    if (handlers == null || !_agents.any((a) => a.id == id)) return false;
    final handler = handlers[answer] ?? handlers[AgentAnswer.dismiss];
    if (handler == null) return false;
    _answers.remove(id);
    handler(now);
    return true;
  }

  /// Removes every agent and every pending event.
  bool stop() {
    final changed = _agents.isNotEmpty || _events.isNotEmpty;
    _agents.clear();
    _events.clear();
    _answers.clear();
    return changed;
  }

  /// The full scenario, starting at [now].
  void startScenario(double now) {
    stop();
    _at(now, (t) => _add('refacto', 'Refacto API', AgentStatus.working, 'Edit src/routes.rs', t, progress: .35, rate: .012));
    _at(now + 1.2, (t) => _add('vitrine', 'Site vitrine', AgentStatus.thinking, 'Lecture de package.json', t));
    _at(now + 2.5, (t) => _add('scraper', 'VPS · scraper', AgentStatus.searching, 'grep -r "proxy" src/', t));
    _at(now + 4, (t) => _set('vitrine', AgentStatus.working, t, detail: 'npm test', progress: .1, rate: .02));
    _at(now + 6, (t) => _set('scraper', AgentStatus.working, t, detail: 'cargo build', progress: .2, rate: .03));
    _at(now + 9, (t) {
      _set('scraper', AgentStatus.approval, t, detail: 'rm -rf ./cache && cargo build --release', clearProgress: true);
      _answers['scraper'] = {
        AgentAnswer.allow: (t) {
          _set('scraper', AgentStatus.working, t, detail: 'cargo build --release', progress: .5, rate: .08);
          _at(t + 6, (t) => _finish('scraper', 'Build release prêt · 2 min 3 s', t));
        },
        AgentAnswer.deny: (t) {
          _set('scraper', AgentStatus.thinking, t, detail: 'Je cherche une autre méthode', clearProgress: true);
          _at(t + 5, (t) => _finish('scraper', 'Arrêté à ta demande, rien supprimé', t));
        },
      };
    });
    _at(now + 16, (t) {
      _set('vitrine', AgentStatus.error, t, detail: 'error: 3 tests échoués (auth.spec.ts)', clearProgress: true);
      _answers['vitrine'] = {
        AgentAnswer.retry: (t) {
          _set('vitrine', AgentStatus.working, t, detail: 'npm test', progress: .3, rate: .05);
          _at(t + 8, (t) => _finish('vitrine', '42 tests passés', t));
        },
        AgentAnswer.dismiss: (t) => _remove('vitrine'),
      };
    });
    _at(now + 24, (t) => _finish('refacto', '14 tests passés · 2 fichiers modifiés', t));
  }

  static const _extras = [
    ('Docs API', 'Edit docs/README.md'),
    ('Migration SQL', 'psql -f 0042_users.sql'),
    ('Tests e2e', 'npx playwright test'),
    ('Bot Discord', 'Edit src/commands/ping.ts'),
    ('Landing page', 'Edit app/page.tsx'),
    ('Script backup', 'rsync -a ~/projets /mnt/backup'),
  ];

  /// One more agent at work, that finishes on its own after 25 to 45 s.
  String addAgent(double now) {
    final (name, detail) = _extras[_added % _extras.length];
    final id = 'extra-${_added++}';
    _add(id, name, AgentStatus.working, detail, now, progress: .05, rate: .02 + _random.nextDouble() * .02);
    _at(now + 25 + _random.nextDouble() * 20, (t) => _finish(id, 'Terminé sans erreur', t));
    return id;
  }

  void _at(double at, void Function(double) run) {
    var i = _events.length;
    while (i > 0 && _events[i - 1].$1 > at) {
      i--;
    }
    _events.insert(i, (at, run));
  }

  void _add(String id, String name, AgentStatus status, String detail, double now, {double? progress, double rate = 0}) {
    _agents.add(Agent(
      id: id,
      name: name,
      status: status,
      detail: detail,
      startedAt: now,
      statusSince: now,
      progress: progress,
      progressRate: rate,
    ));
  }

  void _set(String id, AgentStatus status, double now,
      {String? detail, double? progress, double? rate, bool clearProgress = false}) {
    final i = _agents.indexWhere((a) => a.id == id);
    if (i < 0) return;
    _agents[i] = _agents[i].copyWith(
      status: status,
      statusSince: now,
      detail: detail,
      progress: progress,
      progressRate: rate,
      clearProgress: clearProgress,
    );
  }

  void _finish(String id, String result, double now) {
    _set(id, AgentStatus.finished, now, detail: result);
    _answers.remove(id);
    _at(now + finishedLinger, (_) => _remove(id));
  }

  void _remove(String id) {
    _agents.removeWhere((a) => a.id == id);
    _answers.remove(id);
  }
}
