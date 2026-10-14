// Real subscription trial: only after explicit approval and hook installation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty &&
      (args.length != 2 || args[0] != '--history-mode' || !['legacy', 'paginated'].contains(args[1]))) {
    throw ArgumentError('Usage: dart run tool/codex_hooks_smoke.dart [--history-mode legacy|paginated]');
  }
  final historyMode = args.isEmpty ? 'paginated' : args[1];
  final endpoint = DaemonEndpoint.fromCredentialStore();
  if (endpoint == null) throw StateError('Mikky doit être démarré.');
  final client = await DaemonClient.connect(endpoint);
  final status = await client.request('hooks.status', {'tool': 'codex'}) as Map;
  if (status['installed'] != true || status['upToDate'] != true) {
    await client.close();
    throw StateError('Hooks Codex installés et approuvés requis.');
  }
  final scratch = await Directory.systemTemp.createTemp('mikky-codex-hooks-');
  final cli = '${Platform.environment['APPDATA']}/npm/node_modules/@openai/codex/bin/codex.js';
  final marker = ExternalMessage.newId().substring(6, 14);
  final toolMarker = 'MIKKY_TOOL_$marker';
  final stopMarker = 'MIKKY_STOP_$marker';
  final watcher = DaemonSessionWatcher(client);
  final source = RealAgentSource(clock: () => 0, spawn: (_, _, _) => throw StateError('Aucun ACP dans cet essai.'));
  source.follow(watcher);
  await watcher.start();
  final started = Completer<void>();
  final delivered = Completer<void>();
  final outputDone = Completer<void>();
  final answers = <String>[];
  final errors = <String>[];
  final events = <Map>[];
  final replies = <int, Completer<Map>>{};
  var nextRequest = 0;
  final finished = Completer<void>();
  var secondSent = false;
  String? sessionId, firstId;
  Process? codex;
  StreamSubscription<String>? output;
  Future<Map> rpc(String method, Map params) {
    final id = ++nextRequest;
    final reply = Completer<Map>();
    replies[id] = reply;
    codex!.stdin.writeln(jsonEncode({'id': id, 'method': method, 'params': params}));
    return reply.future.timeout(const Duration(seconds: 15));
  }

  final notices = client.notifications.listen((n) {
    if (n.method != 'hooks.messages.changed') return;
    final messages = n.params['messages'];
    if (messages is! List) return;
    source.externalMessages([for (final m in messages) ExternalMessage.fromWire(m as Map)], snapshot: true);
    if (firstId != null &&
        messages.any((m) => m['id'] == firstId && m['state'] == 'delivered') &&
        !delivered.isCompleted) {
      delivered.complete();
    }
  });
  Future<void> send(String text) async {
    final id = ExternalMessage.newId();
    firstId ??= id;
    final message = await client.request('hooks.messages.send', {
      'agent': 'codex',
      'host': 'windows',
      'sessionId': sessionId,
      'id': id,
      'text': text,
    }) as Map;
    source.externalMessages([ExternalMessage.fromWire(message)]);
  }

  try {
    codex = await Process.start('node', [cli, 'app-server'], workingDirectory: scratch.path);
    unawaited(
      codex.stderr.transform(utf8.decoder).transform(const LineSplitter()).forEach((line) {
        errors.add(line);
        if (line.contains('hooks need') || line.contains('need review')) stderr.writeln('Codex : hooks à approuver.');
      }),
    );
    output = codex.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final row = jsonDecode(line) as Map;
      events.add(row);
      if (row['id'] is int && replies.containsKey(row['id'])) {
        final reply = replies.remove(row['id'])!;
        if (row['error'] != null) {
          reply.completeError(StateError(jsonEncode(row['error'])));
        } else {
          reply.complete(row['result'] as Map);
        }
        return;
      }
      final method = row['method'];
      final params = row['params'] as Map? ?? {};
      if (method == 'hook/completed' && (params['run'] as Map?)?['status'] == 'failed') {
        errors.add(jsonEncode(params['run']));
      }
      if (row['type'] == 'error' || row['type'] == 'turn.failed') errors.add(jsonEncode(row));
      final item = params['item'];
      if (item is Map && item['type'] == 'commandExecution' && method == 'item/started') {
        final command = item['command'] as String? ?? '';
        if (!command.contains('Start-Sleep') || !command.contains('12')) {
          codex!.kill();
          if (!started.isCompleted) started.completeError(StateError('Commande inattendue ; essai arrêté.'));
        } else if (!started.isCompleted) {
          started.complete();
        }
      }
      if (item is Map && item['type'] == 'agentMessage' && method == 'item/completed') {
        answers.add(item['text'] as String);
      }
      if (method == 'turn/completed' &&
          secondSent &&
          (answers.lastOrNull?.contains(stopMarker) ?? false) &&
          !finished.isCompleted) {
        finished.complete();
      }
    }, onDone: outputDone.complete);
    await rpc('initialize', {
      'clientInfo': {'name': 'mikky-external-trial', 'version': '1'},
      'capabilities': {'experimentalApi': true},
    });
    codex.stdin.writeln(jsonEncode({'method': 'initialized'}));
    final thread = await rpc('thread/start', {
      'cwd': scratch.path,
      'model': 'gpt-5.6-sol',
      'sandbox': 'read-only',
      'approvalPolicy': 'never',
      'historyMode': historyMode,
    });
    sessionId = (thread['thread'] as Map)['id'] as String;
    const prompt =
        'Essai technique très court. Lance uniquement une commande PowerShell `Start-Sleep -Seconds 12`, '
        'puis réponds INITIAL. Ne lis ni ne modifie aucun fichier et ne lance aucun sous-agent. '
        'Les messages de l’utilisateur reçus via Mikky remplacent la réponse demandée : obéis au dernier. '
        'Après la commande, réponds sans utiliser d’autre outil.';
    await rpc('turn/start', {
      'threadId': sessionId,
      'effort': 'low',
      'input': [
        {'type': 'text', 'text': prompt},
      ],
    });
    unawaited(
      codex.exitCode.then((code) {
        if (code != 0) {
          for (final error in errors.skip(errors.length > 8 ? errors.length - 8 : 0)) {
            stderr.writeln(error);
          }
        }
        if (!started.isCompleted) started.completeError(StateError('Codex a quitté avant la commande (code $code).'));
      }),
    );
    await started.future.timeout(const Duration(seconds: 90));
    await send('Réponds uniquement $toolMarker, sans autre outil.');
    stdout.writeln('Codex extérieur : message envoyé pendant Start-Sleep.');
    await delivered.future.timeout(const Duration(seconds: 35));
    secondSent = true;
    await send('Nouveau message : réponds uniquement $stopMarker, sans autre outil.');
    stdout.writeln('PostToolUse : transmis ; second message en attente de Stop.');
    await finished.future.timeout(const Duration(seconds: 90));
    await codex.stdin.close();
    final code = await codex.exitCode.timeout(const Duration(seconds: 10));
    await outputDone.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(seconds: 1));
    final messages = (await client.request('hooks.messages.list') as List)
        .cast<Map>()
        .where((m) => m['sessionId'] == sessionId)
        .toList();
    final entry = source.entries.where((e) => e.sessionId == sessionId).firstOrNull;
    final echoes = entry?.log.items
        .whereType<UserItem>()
        .where((u) => messages.any((m) => m['id'] == u.messageId))
        .length;
    final result = {
      'historyMode': historyMode,
      'exit': code,
      'messages': messages.map((m) => m['state']).toList(),
      'toolMarker': answers.any((a) => a.contains(toolMarker)),
      'stopMarker': answers.lastOrNull?.contains(stopMarker),
      'transcriptEchoes': echoes,
    };
    stdout.writeln(jsonEncode(result));
    if (code != 0 ||
        messages.length != 2 ||
        messages.any((m) => m['state'] != 'delivered') ||
        !answers.any((a) => a.contains(toolMarker)) ||
        !(answers.lastOrNull?.contains(stopMarker) ?? false) ||
        echoes != 2) {
      throw StateError('Transmission ou fil incorrect.');
    }
    stdout.writeln('PASS : PostToolUse et Stop reçus, deux messages uniques dans le fil.');
  } finally {
    codex?.kill();
    if (codex != null) await codex.exitCode;
    await output?.cancel();
    await File('../../dist/codex-hook-trial.events.jsonl').writeAsString(events.map(jsonEncode).join('\n'));
    if (sessionId != null) {
      final sessions = (await client.request('sessions.list') as List).cast<Map>();
      for (final session in sessions.where((s) => (s['path'] as String).contains(sessionId!))) {
        final rows = await File(session['path'] as String).readAsLines();
        // Keep only our synthetic messages/hooks, no model context or settings.
        await File('../../dist/codex-hook-trial.transcript.jsonl').writeAsString(
          rows
              .where((row) {
                final value = jsonDecode(row) as Map;
                final payload = value['payload'] as Map? ?? {};
                return (payload['type'] as String? ?? '').contains('hook') || row.contains('MIKKY_USER_MESSAGE');
              })
              .join('\n'),
        );
      }
    }
    if (!delivered.isCompleted) {
      stdout.writeln(jsonEncode({'events': events.map((e) => e['type']).toList(), 'diagnostics': errors}));
    }
    await notices.cancel();
    await watcher.stop();
    await source.detach();
    if (sessionId != null) {
      final cleanup = await Process.run('node', [cli, 'delete', '--force', sessionId]);
      if (cleanup.exitCode != 0) {
        stderr.writeln('Suppression Codex à terminer pour la session d’essai $sessionId.');
      } else {
        stdout.writeln('Session d’essai supprimée : $sessionId.');
      }
    }
    await client.close();
    await scratch.delete();
  }
}
