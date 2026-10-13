// Real subscription prompt: run only with the user's approval.
// Uses the installed Claude hooks and deletes only its own session afterwards.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) throw ArgumentError('Usage: dart run tool/claude_hooks_smoke.dart');
  final endpoint = DaemonEndpoint.fromCredentialStore();
  if (endpoint == null) throw StateError('Mikky doit être démarré.');
  final client = await DaemonClient.connect(endpoint);
  final hookStatus = await client.request('hooks.status', {'tool': 'claude'}) as Map;
  if (hookStatus['installed'] != true || hookStatus['upToDate'] != true) {
    await client.close();
    throw StateError('Hooks Claude requis ; aucune installation automatique.');
  }
  final scratch = await Directory.systemTemp.createTemp('mikky-claude-hooks-');
  final raw = ExternalMessage.newId().substring(6);
  final sessionId =
      '${raw.substring(0, 8)}-${raw.substring(8, 12)}-4${raw.substring(13, 16)}-a${raw.substring(17, 20)}-${raw.substring(20)}';
  final toolMarker = 'MIKKY_TOOL_${raw.substring(0, 8)}';
  final stopMarker = 'MIKKY_STOP_${raw.substring(0, 8)}';
  final watcher = DaemonSessionWatcher(client);
  final source = RealAgentSource(clock: () => 0, spawn: (_, _, _) => throw StateError('Aucun ACP dans cet essai.'));
  source.enqueueExternal = (e, id, text) async => ExternalMessage.fromWire(
    await client.request('hooks.messages.send', {'agent': 'claude', 'sessionId': e.sessionId, 'id': id, 'text': text})
        as Map,
  );
  source.follow(watcher);
  await watcher.start();
  final started = Completer<void>();
  final firstDelivery = Completer<void>();
  String? firstMessage;
  final answers = <String>[];
  Process? claude;
  StreamSubscription<String>? output;
  final notifications = client.notifications.listen((n) {
    if (n.method != 'hooks.messages.changed') return;
    final messages = n.params['messages'];
    if (messages is! List) return;
    source.externalMessages([for (final m in messages) ExternalMessage.fromWire(m as Map)], snapshot: true);
    if (firstMessage != null &&
        messages.any((m) => m['id'] == firstMessage && m['state'] == 'delivered') &&
        !firstDelivery.isCompleted) {
      firstDelivery.complete();
    }
  });
  const initialPrompt =
      'Essai technique : lance exactement une commande Bash `sleep 12`, puis réponds INITIAL. '
      'Ne lis ni ne modifie aucun fichier, aucun sous-agent. '
      'Les messages de l’utilisateur reçus via Mikky remplacent la réponse demandée ; obéis au dernier.';
  try {
    final home = Platform.environment['USERPROFILE']!;
    claude = await Process.start('$home/.local/bin/claude.exe', [
      '--print',
      '--verbose',
      '--output-format',
      'stream-json',
      '--session-id',
      sessionId,
      '--model',
      'sonnet',
      '--effort',
      'low',
      '--max-turns',
      '4',
      '--tools',
      'Bash',
      '--allowedTools',
      'Bash(sleep 12)',
      '--disable-slash-commands',
      '--setting-sources',
      'user',
      '--strict-mcp-config',
      '--mcp-config',
      '{"mcpServers":{}}',
      '--',
      initialPrompt,
    ], workingDirectory: scratch.path);
    unawaited(claude.stderr.drain<void>());
    await claude.stdin.close();
    unawaited(
      claude.exitCode.then((code) {
        if (!started.isCompleted) started.completeError(StateError('Claude a quitté avant l’outil (code $code).'));
      }),
    );
    output = claude.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final row = jsonDecode(line) as Map;
      if (row['type'] != 'assistant') return;
      for (final block in (row['message'] as Map)['content'] as List) {
        if (block['type'] == 'text') answers.add(block['text'] as String);
        if (block['type'] == 'tool_use') {
          if (block['name'] != 'Bash' || block['input']['command'] != 'sleep 12') {
            claude!.kill();
            if (!started.isCompleted) started.completeError(StateError('Outil inattendu ; essai arrêté.'));
          } else if (!started.isCompleted) {
            started.complete();
          }
        }
      }
    });
    await started.future.timeout(const Duration(seconds: 90));
    AgentEntry? entry;
    for (var i = 0; i < 100; i++) {
      entry = source.entries.where((e) => e.sessionId == sessionId).firstOrNull;
      if (entry != null && entry.log.working) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (entry == null || !entry.log.working) throw StateError('Session extérieure non suivie.');
    await source.send(entry.id, 'Réponds uniquement $toolMarker, sans autre outil.');
    firstMessage = source.messagesOf(entry.id).single.id;
    stdout.writeln('Claude extérieur : message envoyé pendant sleep 12.');
    await firstDelivery.future.timeout(const Duration(seconds: 30));
    await source.send(entry.id, 'Nouveau message : réponds uniquement $stopMarker, sans autre outil.');
    stdout.writeln('PostToolUse : transmis ; second message en attente de Stop.');
    final code = await claude.exitCode.timeout(const Duration(seconds: 90));
    // Finish consuming the stream and allow the file watcher its debounce.
    await Future<void>.delayed(const Duration(seconds: 1));
    final messages = source.messagesOf(entry.id);
    final users = entry.log.items.whereType<UserItem>().where((u) => messages.any((m) => m.id == u.messageId)).toList();
    if (code != 0 ||
        messages.length != 2 ||
        messages.any((m) => !m.delivered) ||
        users.length != 2 ||
        !answers.any((a) => a.contains(toolMarker)) ||
        !answers.last.contains(stopMarker)) {
      stdout.writeln(
        jsonEncode({
          'exit': code,
          'messages': messages.map((m) => m.delivered).toList(),
          'echoes': users.length,
          'toolMarker': answers.any((a) => a.contains(toolMarker)),
          'stopMarker': answers.lastOrNull?.contains(stopMarker),
        }),
      );
      throw StateError('Transmission ou fil incorrect.');
    }
    stdout.writeln('PASS : PostToolUse et Stop pris en compte, deux messages uniques dans le fil.');
  } finally {
    claude?.kill();
    if (claude != null) await claude.exitCode;
    await output?.cancel();
    await notifications.cancel();
    await watcher.stop();
    await source.detach();
    // Remove only this UUID, in the transcript roots, after the process exits.
    final sessions = await client.request('sessions.list') as List;
    for (final s in sessions.cast<Map>().where((s) => (s['path'] as String).endsWith('$sessionId.jsonl'))) {
      await client.request('sessions.delete', {'path': s['path']});
    }
    final roots = [
      Directory('${Platform.environment['USERPROFILE']}/.claude/projects'),
      Directory('${Platform.environment['USERPROFILE']}/.claude/tasks'),
    ];
    for (final root in roots.where((d) => d.existsSync())) {
      for (final f
          in root
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.uri.pathSegments.last == '$sessionId.jsonl')) {
        await f.delete();
      }
    }
    final scratchName = scratch.path.split(Platform.pathSeparator).last;
    for (final project in roots.first.listSync().whereType<Directory>().where((d) => d.path.endsWith(scratchName))) {
      final memory = Directory('${project.path}/memory');
      if (memory.existsSync() && memory.listSync().isEmpty) await memory.delete();
      if (project.listSync().isEmpty) await project.delete();
    }
    await client.close();
    await scratch.delete();
    stdout.writeln('Session d’essai supprimée : $sessionId.');
  }
}
