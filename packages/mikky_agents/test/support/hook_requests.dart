import 'package:mikky_agents/mikky_agents.dart';

/// A permission as `mikkyd` lists it (`hooks.list`), its event made in Rust.
HookAsk permissionAsk(int id, String session, String command, {String? cwd, bool answerable = true}) =>
    HookAsk.fromJson({
      'id': id,
      'sessionId': session,
      'cwd': ?cwd,
      'agent': 'claude',
      'answerable': answerable,
      'event': {
        'type': 'permission',
        'id': 'hook:$id',
        'title': 'Bash $command',
        'command': command,
        'toolCallId': 'toolu_$id',
        'options': [
          {'optionId': 'allow', 'name': 'Oui', 'kind': 'allow_once'},
          {'optionId': 'deny', 'name': 'Non', 'kind': 'reject_once'},
        ],
      },
    })!;

/// Claude's question « Quelle base ? » (SQLite, Postgres) then « Quels
/// tests ? » (several), as `mikkyd` lists it.
HookAsk questionAsk(int id, String session, {String? cwd, bool answerable = true}) => HookAsk.fromJson({
  'id': id,
  'sessionId': session,
  'cwd': ?cwd,
  'agent': 'claude',
  'answerable': answerable,
  'event': {
    'type': 'question',
    'id': 'hook:$id',
    'message': 'Quelle base ?',
    'questions': [
      {
        'key': 'q1',
        'otherKey': 'q1_custom',
        'text': 'Quelle base ?',
        'title': 'Base',
        'multiple': false,
        'choices': [
          {'value': 'SQLite', 'description': 'Un fichier'},
          {'value': 'Postgres', 'description': 'Un serveur'},
        ],
      },
      {
        'key': 'q2',
        'otherKey': 'q2_custom',
        'text': 'Quels tests ?',
        'title': null,
        'multiple': true,
        'choices': [
          {'value': 'Unitaires', 'description': ''},
          {'value': 'Bout en bout', 'description': ''},
        ],
      },
    ],
  },
})!;
