// Deterministic visual walkthrough through the real watcher and hook API.
// No model, subscription prompt, shell tool or hook installation is involved.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_agents/src/daemon/session_wire.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'notch_walkthrough/questions.dart';
import 'notch_walkthrough/transcript.dart';

Future<void> main(List<String> args) async {
  if (args.any((a) => a != '--verify')) throw ArgumentError('Usage : dart run tool/notch_walkthrough.dart [--verify]');
  final verify = args.contains('--verify');
  Directory? temporaryHome;
  Process? backend;
  DaemonClient? client;
  final hooks = <DaemonClient>{};
  final transcripts = <WalkthroughTranscript>[];
  final report = <Map<String, Object?>>[];
  final cancelled = Completer<void>();
  StreamSubscription<ProcessSignal>? interrupt;
  StreamIterator<String>? input;
  final runId = 'mikky-notch-test-${DateTime.now().microsecondsSinceEpoch}';
  Future<void> progress(String step, String state) async {
    if (verify) return;
    final file = File('../../dist/notch-test-live.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'run': runId, 'pid': pid, 'step': step, 'state': state}));
  }

  Future<T> active<T>(Future<T> work) => Future.any([work, cancelled.future.then<T>((_) => throw const _Cancelled())]);
  try {
    var endpoint = DaemonEndpoint.fromCredentialStore();
    var home = Platform.environment['USERPROFILE']!;
    if (verify) {
      temporaryHome = await Directory.systemTemp.createTemp('mikky-notch-verify-');
      home = temporaryHome.path;
      await Directory('$home/.claude/projects').create(recursive: true);
      await Directory('$home/.codex/sessions').create(recursive: true);
      backend = await Process.start('../../daemon/target/debug/mikkyd.exe', [
        '--stdout-endpoint',
        '--watch-home',
        home,
      ]);
      unawaited(backend.stderr.drain<void>());
      endpoint = DaemonEndpoint.parse(
        await backend.stdout.transform(utf8.decoder).transform(const LineSplitter()).first,
      );
    }
    if (endpoint == null) throw StateError('Démarre Mikky avant ce test.');
    final connection = await DaemonClient.connect(endpoint);
    client = connection;
    await connection.request('hello');
    if (!verify) {
      input = StreamIterator(stdin.transform(utf8.decoder).transform(const LineSplitter()));
      interrupt = ProcessSignal.sigint.watch().listen((_) {
        if (!cancelled.isCompleted) cancelled.complete();
      });
    }
    final main = WalkthroughTranscript(Directory('$home/.claude/projects/$runId'), '$runId-claude');
    final other = WalkthroughTranscript(Directory('$home/.codex/sessions/$runId'), '$runId-codex', codex: true);
    transcripts.addAll([main, other]);

    Future<void> checkpoint(String title, String instructions) async {
      stdout.writeln('\n=== $title ===\n$instructions');
      final observation = <String, Object?>{'step': title, 'at': DateTime.now().toIso8601String()};
      report.add(observation);
      if (verify) return;
      await progress(title, 'waiting-console');
      stdout.writeln(
        'Entrée : continuer · remarque puis Entrée : noter et continuer · q : nettoyer · Ctrl+C : arrêter',
      );
      if (!await active(input!.moveNext())) throw const _Cancelled();
      final note = input!.current.trim();
      if (note.toLowerCase() == 'q') throw const _Cancelled();
      if (note.isNotEmpty) observation['note'] = note;
    }

    Future<SessionLog> waitFor(WalkthroughTranscript transcript, bool Function(SessionLog) predicate) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        try {
          final log = SessionLog();
          var after = 0;
          var more = true;
          while (more) {
            final page = await connection.request('sessions.read', {'path': transcript.apiPath, 'after': after}) as Map;
            for (final row in page['lines'] as List) {
              final event = sessionEventFromWire((row as Map).cast<String, dynamic>());
              if (event != null) log.apply(event);
            }
            after = page['next'] as int;
            more = page['more'] == true;
          }
          if (predicate(log)) return log;
        } on DaemonError {
          /* The native watcher has not imported the file yet. */
        }
        await active(Future<void>.delayed(const Duration(milliseconds: 100)));
      }
      throw StateError('Le moteur n’a pas observé l’état attendu pour ${transcript.id}.');
    }

    Future<Map> ask(
      WalkthroughTranscript transcript,
      String toolId,
      String tool,
      Map<String, Object?> data, {
      Map<String, Object>? automatic,
      String decision = 'allow',
    }) async {
      await transcript.tool(toolId, tool, data);
      // A separate connection can be closed to release only this test request.
      final hook = await DaemonClient.connect(endpoint!);
      hooks.add(hook);
      try {
        for (var attempt = 0; attempt < 10; attempt++) {
          await progress(tool, 'waiting-notch');
          final pending = hook.request('hook.event', {
            'payload': {
              'hook_event_name': 'PermissionRequest',
              'session_id': transcript.id,
              'cwd': transcript.folder.path,
              'tool_name': tool,
              'tool_use_id': toolId,
              'tool_input': data,
              'mikky_agent': transcript.codex ? 'codex' : 'claude',
            },
          });
          if (verify) {
            final deadline = DateTime.now().add(const Duration(seconds: 5));
            Map? request;
            while (request == null && DateTime.now().isBefore(deadline)) {
              final listed = await connection.request('hooks.list') as List;
              request = listed.cast<Map>().where((r) => r['sessionId'] == transcript.id).firstOrNull;
              if (request == null) await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            if (request == null) throw StateError('La demande n’est pas arrivée au moteur.');
            final accepted = await connection.request('hooks.answer', {
              'id': request['id'],
              if (automatic != null) 'answers': automatic else 'decision': decision,
            });
            if (accepted != true) throw StateError('Le moteur a refusé la réponse de vérification.');
          }
          final reply = await active(pending) as Map;
          if (reply['answers'] != null || reply['decision'] != null) {
            report.add({'tool': tool, 'reply': reply});
            await transcript.result(toolId, reply, denied: reply['decision'] == 'deny');
            await transcript.say('TEST · Réponse reçue : ${jsonEncode(reply)}');
            stdout.writeln('Réponse reçue : ${jsonEncode(reply)}');
            return reply;
          }
          stdout.writeln('La demande a expiré ou a été laissée à l’application : je la repropose.');
        }
        throw StateError('Test sans réponse depuis trop longtemps.');
      } finally {
        await hook.close();
        hooks.remove(hook);
      }
    }

    stdout.writeln(
      'TEST VISUEL DE LA NOTCH\nScénario simulé, vrai moteur et vraies interactions. Aucun modèle appelé.',
    );
    await checkpoint(
      'Départ',
      'Ouvre la notch. Une tâche TEST NOTCH va apparaître. Les autres conversations restent en place.',
    );
    await main.begin('TEST NOTCH · Parcours visuel complet : autorisations, questions, limite et reprise.');
    await main.say('Je prépare un atelier fictif. Aucune commande montrée ne sera exécutée. Réponds dans la notch.');
    await main.tool('read', 'Read', {'file_path': 'TEST-NOTCH-fichier-fictif.md'});
    await waitFor(main, (log) => log.statusAt(DateTime.now()).isBusy);
    await checkpoint(
      '1 · Activité',
      'Vérifie la tâche, son nom, son état et le son de démarrage. Entre dans le fil, puis reviens à l’accueil.',
    );
    await main.result('read', 'Lecture simulée terminée.');
    for (final allow in [true, false]) {
      stdout.writeln(
        '\n${allow ? '2 · Clique Oui' : '3 · Clique Non'} dans la notch. Plus tard permet de différer puis rouvrir la demande.',
      );
      await ask(main, allow ? 'yes' : 'no', 'Bash', {
        'command': 'Write-Output "TEST NOTCH · ${allow ? 'autoriser' : 'refuser'}"',
        'description': 'SIMULATION : ${allow ? 'teste Oui' : 'teste Non'}, aucune commande exécutée.',
      }, decision: allow ? 'allow' : 'deny');
      await checkpoint(
        'Observer le retour au travail',
        'La réponse doit retirer la demande et reprendre la tâche une seule fois.',
      );
    }
    final forms = walkthroughForms();
    final labels = [
      '4 · Choix simple',
      '5 · Choix multiples',
      '6 · Réponse libre',
      '7 · Série de questions',
      '8 · Texte long et Plus tard',
    ];
    for (var i = 0; i < forms.length; i++) {
      await main.say('TEST · ${labels[i]}. Le contexte doit rester au-dessus du bloc indicateurs / question / choix.');
      stdout.writeln('\n${labels[i]} : réponds dans la notch.${i == 2 ? ' Choisis Autre et écris une réponse.' : ''}');
      await ask(main, 'question-$i', 'AskUserQuestion', {
        'questions': forms[i],
      }, automatic: walkthroughAnswers(i, forms[i]));
      await checkpoint(
        'Inspecter après la réponse',
        'Vérifie le fil et le retour à la tâche. Tu peux prendre des captures avant de continuer.',
      );
    }
    await other.begin('TEST NOTCH · Deuxième agent Codex pendant que Claude continue.');
    await other.say('Je suis le deuxième agent simulé. Vérifie que les deux conversations restent distinctes.');
    await waitFor(other, (log) => log.statusAt(DateTime.now()).isBusy);
    await checkpoint('9 · Deux agents', 'Observe les deux tuiles et passe de Claude à Codex.');
    stdout.writeln(
      '\n10 · Deux questions simultanées. Réponds à chaque agent ; les formulaires doivent rester indépendants.',
    );
    await Future.wait([
      ask(main, 'parallel-claude', 'AskUserQuestion', {
        'questions': forms.first,
      }, automatic: walkthroughAnswers(0, forms.first)),
      ask(other, 'parallel-codex', 'AskUserQuestion', {
        'questions': forms[1],
      }, automatic: walkthroughAnswers(1, forms[1])),
    ]);
    await checkpoint('Observer les deux réponses', 'Aucune réponse ne doit être envoyée à l’autre conversation.');
    await other.event('error', {
      'message': 'TEST NOTCH : erreur simulée, aucun travail réel perdu.',
      'codex_error_info': 'other',
    });
    await waitFor(other, (log) => log.statusAt(DateTime.now()) == AgentStatus.error);
    await checkpoint('11 · Erreur Codex', 'Observe l’erreur, sa conversation et le son.');
    await main.limit();
    await waitFor(main, (log) => log.statusAt(DateTime.now()) == AgentStatus.rateLimited);
    await checkpoint(
      '12 · Limite simulée Claude',
      'La limite est fictive. Observe le jaune et l’heure. Ne programme pas de relance automatique pour ce test.',
    );
    await main.resume();
    await main.say('TEST · La conversation reprend dans son application, dans la même session.');
    await waitFor(main, (log) => log.statusAt(DateTime.now()).isBusy && log.limitSource == null);
    await checkpoint(
      '13 · Reprise dans la même conversation',
      'Le jaune doit disparaître, le travail reprendre sans nouvelle tuile. Codex reste volontairement en erreur. Écoute le son de reprise.',
    );
    await other.event('task_started');
    await other.event('user_message', {'message': 'TEST · Codex reprend après son erreur.'});
    await other.say('TEST · Erreur résolue, deuxième agent terminé.', end: true);
    await waitFor(other, (log) => log.statusAt(DateTime.now()) == AgentStatus.finished);
    await main.say('TEST NOTCH terminé. Toutes les réponses ont été enregistrées dans le rapport local.', end: true);
    await waitFor(main, (log) => log.statusAt(DateTime.now()) == AgentStatus.finished);
    await checkpoint(
      '14 · Terminé',
      'Les deux agents sont terminés : aucun point d’exclamation ni étoile bleue ne doit rester. Observe le son et l’historique. Entrée nettoie le test.',
    );
    if (verify && report.where((row) => row.containsKey('reply')).length != 9) {
      throw StateError('La vérification doit recevoir exactement neuf réponses.');
    }
  } on _Cancelled {
    stdout.writeln('\nArrêt demandé. Nettoyage du test.');
  } finally {
    Future<void> clean(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        report.add({'cleanupError': '$error'});
        stderr.writeln('Nettoyage incomplet : $error');
      }
    }

    for (final hook in hooks) {
      await clean(hook.close);
    }
    for (final transcript in transcripts) {
      if (client != null && !client.isClosed && await transcript.file.exists()) {
        await clean(() async {
          await client!.request('state.patch', {
            'marks': {
              '${transcript.codex ? 'codex' : 'claude'}:${transcript.id}': {'forgotten': true},
            },
          });
        });
        if (await transcript.file.exists()) {
          try {
            await client.request('sessions.delete', {'path': transcript.apiPath});
          } on DaemonError catch (error) {
            stderr.writeln('Nettoyage de l’index : ${error.message}');
          }
        }
      }
      await clean(() async {
        if (await transcript.file.exists()) await transcript.file.delete();
        if (await transcript.folder.exists() && await transcript.folder.list().isEmpty) {
          await transcript.folder.delete();
        }
      });
    }
    await clean(() async {
      await client?.close();
    });
    await input?.cancel();
    await interrupt?.cancel();
    if (backend != null) {
      await backend.stdin.close();
      try {
        await backend.exitCode.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        backend.kill();
      }
    }
    if (temporaryHome != null) {
      final root = Directory.systemTemp.absolute.path;
      final target = temporaryHome.absolute;
      if (target.parent.path.toLowerCase() != root.toLowerCase() ||
          !target.path.split(Platform.pathSeparator).last.startsWith('mikky-notch-verify-')) {
        throw StateError('Le dossier temporaire de vérification est hors du répertoire attendu.');
      }
      await target.delete(recursive: true);
    } else {
      final file = File('../../dist/$runId-report.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      stdout.writeln('Rapport : ${file.absolute.path}');
      await progress('Fin', 'finished');
    }
    stdout.writeln(
      report.any((row) => row.containsKey('cleanupError'))
          ? 'Consulte les erreurs de nettoyage dans le rapport.'
          : 'Test nettoyé.',
    );
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
