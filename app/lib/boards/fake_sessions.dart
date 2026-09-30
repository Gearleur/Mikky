import 'package:mikky_engine/mikky_engine.dart';

/// Made-up sessions for the boards: every state an agent's page can be
/// in, built from the same events Claude and Codex send.
abstract final class FakeSessions {
  static final _t0 = DateTime(2026, 9, 30, 14, 0);
  static const _dir = r'C:\Users\alexa\projet\mikky';
  static const _file = r'C:\Users\alexa\projet\mikky\packages\mikky_engine\lib\src\island\island_machine.dart';

  static DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

  static SessionLog _log(List<SessionEvent> events) => SessionLog()..applyAll(events);

  static List<SessionEvent> _start(String ask) => [
    SessionStarted('s', cwd: _dir, at: _at(0)),
    // As the agents send it: the turn, then the message that starts it.
    TurnStarted(at: _at(0)),
    UserMessage(ask, at: _at(0)),
  ];

  /// The first steps of the fix: a plan, the tests that fail, the file read.
  static List<SessionEvent> _fixing() => [
    ..._start('Les tests du moteur cassent sur la fermeture auto, tu peux regarder ?'),
    AgentMessage('Je lance les tests pour voir ce qui casse, puis je regarde la constante.', thought: true, at: _at(3)),
    PlanChanged(const [
      PlanEntry('Lancer les tests', PlanStatus.completed),
      PlanEntry('Corriger la fermeture auto', PlanStatus.inProgress),
      PlanEntry('Relancer les tests', PlanStatus.pending),
    ], at: _at(4)),
    ToolCallEvent('t1', name: 'Bash', kind: ToolKind.execute, title: 'Lancer les tests', command: 'dart test', status: ToolStatus.failed,
        output: '00:02 +74 -2: island closes after 45 s [E]\n  Expected: 45\n    Actual: 60\n00:02 +74 -2: Some tests failed.', at: _at(6)),
    ToolCallEvent('t2', name: 'Read', kind: ToolKind.read, title: 'Lire island_machine.dart', path: _file, status: ToolStatus.completed, at: _at(20)),
  ];

  /// At work, a file being written.
  static SessionLog working() => _log([
    ..._fixing(),
    ToolCallEvent('t3', name: 'Edit', kind: ToolKind.edit, title: 'Modifier island_machine.dart', path: _file,
        diff: const FileDiff(_file, '  static const autoCloseSec = 60;', '  static const autoCloseSec = 45;'), status: ToolStatus.running, at: _at(40)),
  ]);

  /// At work, without a plan: its tools make the steps.
  static SessionLog workingNoPlan() => _log([
    ..._start('Ajoute un test pour le lecteur de sessions Codex.'),
    for (final (i, f) in ['codex_reader.dart', 'session_log.dart', 'codex_reader_test.dart'].indexed)
      ToolCallEvent('r$i', kind: ToolKind.read, title: 'Lire $f', path: 'packages/mikky_engine/lib/src/sessions/$f', status: ToolStatus.completed, at: _at(4 + i)),
    ToolCallEvent('s1', kind: ToolKind.search, title: 'Chercher « token_count »', command: 'rg token_count', status: ToolStatus.completed, at: _at(9)),
    ToolCallEvent('e1', kind: ToolKind.edit, title: 'Écrire usage_test.dart', path: 'packages/mikky_engine/test/sessions/usage_test.dart',
        diff: const FileDiff('packages/mikky_engine/test/sessions/usage_test.dart', null, "test('Codex writes its limits', () {\n  …\n});"),
        status: ToolStatus.completed, at: _at(30)),
    ToolCallEvent('x1', kind: ToolKind.execute, title: 'Lancer les tests', command: 'dart test test/sessions', status: ToolStatus.running, at: _at(50)),
  ]);

  /// Waits for a yes: a command to run.
  static SessionLog approval() => _log([
    ..._fixing(),
    ToolCallEvent('t4', name: 'Bash', kind: ToolKind.execute, title: 'Lancer npm run build', command: 'npm run build', status: ToolStatus.pending, at: _at(60)),
    PermissionAsked(1, toolCallId: 't4', title: 'Terminal', command: 'npm run build', options: const [
      PermissionOption('allow', 'Oui', 'allow_once'),
      PermissionOption('always', 'Toujours', 'allow_always'),
      PermissionOption('reject', 'Non', 'reject_once'),
    ], at: _at(60)),
  ]);

  /// Asks a question with choices.
  static SessionLog question() => _log([
    ..._start('Prépare le stockage des tâches planifiées.'),
    AgentMessage('Avant de commencer, il me faut un choix.', at: _at(3)),
    QuestionAsked(2, message: 'Quelle base de données ?', questions: const [
      Question('db', text: 'Quelle base de données ?', choices: [
        QuestionChoice('SQLite', 'Un fichier, rien à installer'),
        QuestionChoice('Postgres'),
        QuestionChoice('Aucune pour l’instant'),
      ]),
    ], at: _at(4)),
  ]);

  /// Done: two tasks, then the conversation goes on.
  static SessionLog done() => _log([
    ..._fixing(),
    ToolCallEvent('t3', name: 'Edit', kind: ToolKind.edit, title: 'Modifier island_machine.dart', path: _file,
        diff: const FileDiff(_file, '  static const autoCloseSec = 60;', '  static const autoCloseSec = 45;'), status: ToolStatus.completed, at: _at(40)),
    ToolCallEvent('t5', name: 'Bash', kind: ToolKind.execute, title: 'Relancer les tests', command: 'dart test', status: ToolStatus.completed,
        output: '00:02 +76: All tests passed!', at: _at(70)),
    PlanChanged(const [
      PlanEntry('Lancer les tests', PlanStatus.completed),
      PlanEntry('Corriger la fermeture auto', PlanStatus.completed),
      PlanEntry('Relancer les tests', PlanStatus.completed),
    ], at: _at(80)),
    AgentMessage(
      'C’est corrigé : la fermeture auto attendait **60 s**, les tests **45 s**.\n\n'
      '1. J’ai mis `autoCloseSec` à 45\n'
      '2. Les 76 tests passent\n\n'
      '- Rien d’autre ne dépendait de cette valeur\n'
      '- La spec dit bien 45 s (§3)',
      at: _at(90),
    ),
    TurnEnded(StopReason.endTurn, at: _at(92)),
    TurnStarted(at: _at(200)),
    UserMessage('Merci ! Tu peux me donner la commande pour les lancer seul ?', at: _at(200)),
    AgentMessage('Dans `packages/mikky_engine` :\n\n```powershell\nC:\\dev\\flutter\\bin\\dart.bat test\n```\n\nPlus de détails : https://dart.dev/tools/dart-test', at: _at(205)),
    TurnEnded(StopReason.endTurn, at: _at(206)),
  ]);

  /// Stopped by the subscription's limit, as Claude says it.
  static SessionLog limited() => _log([
    ..._fixing(),
    TurnEnded(StopReason.rateLimited, message: '5-hour limit reached ∙ resets 5:10pm', at: _at(45)),
  ]);

  /// Stopped by an error.
  static SessionLog error() => _log([
    ..._fixing(),
    TurnEnded(StopReason.error, message: 'Le processus de l’agent s’est arrêté (code 1).', at: _at(45)),
  ]);

  /// Stopped by the user.
  static SessionLog cancelled() => _log([
    ..._fixing(),
    TurnEnded(StopReason.cancelled, at: _at(30)),
  ]);
}
