// Real subscription prompts: run only with the user's approval.
// Uses an isolated daemon and deletes only the sessions it creates.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

Future<void> main(List<String> args) async {
  if (args.any((arg) => arg != '--codex-only')) {
    throw ArgumentError('Usage : dart run tool/steering_smoke.dart [--codex-only]');
  }
  final scratch = await Directory.systemTemp.createTemp('mikky-steering-');
  final process = await Process.start('../../daemon/target/debug/mikkyd.exe', ['--stdout-endpoint']);
  unawaited(process.stderr.drain<void>());
  final endpoint = DaemonEndpoint.parse(
    await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first,
  )!;
  final client = await DaemonClient.connect(endpoint);
  try {
    final ready = await client.request('tools.status', {'host': 'windows'}) as Map;
    if (ready['ready'] != true) throw StateError('Adaptateurs absents ; aucune installation automatique.');
    for (final provider
        in args.contains('--codex-only') ? [AgentProvider.codex] : [AgentProvider.claude, AgentProvider.codex]) {
      if (!await _exercise(client, provider, scratch.path)) exitCode = 1;
    }
  } finally {
    await client.close();
    await process.stdin.close();
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await scratch.delete();
  }
}

Future<bool> _exercise(DaemonClient client, AgentProvider provider, String cwd) async {
  DaemonAgentRun? run;
  String? session;
  try {
    final auth = await client.request('tools.auth', {'host': 'windows', 'provider': provider.name}) as Map;
    if (auth['loggedIn'] != true) throw StateError('${provider.name} : connexion requise.');
    run = await DaemonAgentRun.launch(client, provider: provider, host: AgentHost.windows, cwd: cwd);
    await run.open(cwd: run.workingDirectory!, mode: modeFor(provider, PermissionMode.ask));
    session = run.sessionId;
    if (provider == AgentProvider.claude) await run.setModel('sonnet');
    if (provider == AgentProvider.codex) {
      final model = run.log.models.where((m) => m.id == 'gpt-6-sol[medium]').firstOrNull;
      if (!run.log.models.any((m) => m.id == run!.log.modelId) && model != null) await run.setModel(model.id);
      stdout.writeln('codex: modèle d’essai=${run.log.modelId}');
    }
    stdout.writeln('${provider.name}: session=$session');
    const prompt =
        'Essai technique dans ce dossier temporaire. Lance une seule commande qui attend 15 secondes '
        '(PowerShell : Start-Sleep -Seconds 15, ou bash : sleep 15). '
        'Ne lis aucun fichier, ne modifie aucun fichier et ne lance aucun sous-agent. '
        'Quand la commande est terminée, réponds uniquement INITIAL.';
    final done = client.request('run.prompt', {'run': run.runId, 'text': prompt});
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    ToolItem? active;
    var started = false;
    while (DateTime.now().isBefore(deadline)) {
      started |= run.log.working;
      for (final permission in run.log.pending) {
        final command = permission.command ?? permission.title;
        if (!command.toLowerCase().contains('sleep') || !command.contains('15')) {
          run.answer(allow: false, requestId: permission.requestId);
          throw StateError('Commande inattendue refusée : $command');
        }
        run.answer(allow: true, requestId: permission.requestId);
      }
      active = run.log.items
          .whereType<ToolItem>()
          .where((t) => t.active && '${t.command ?? ''} ${t.title}'.toLowerCase().contains('sleep'))
          .lastOrNull;
      if (active != null) break;
      if (started && !run.log.working) {
        stdout.writeln('${provider.name}: réponse ACP=${jsonEncode(await done)}');
        throw StateError(
          '${provider.name}: fin avant la commande, raison=${run.log.turns.last.reason}, '
          'erreur=${run.log.turns.last.message}, outils=${run.log.items.whereType<ToolItem>().map((t) => '${t.title}/${t.status}/${t.command}')}, ${run.log.detail}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (active == null) throw StateError('${provider.name}: aucune commande en cours.');
    // Let the command really start, rather than steering its initial tool event.
    await Future<void>.delayed(const Duration(seconds: 1));
    final marker = 'MIKKY_STEER_${DateTime.now().microsecondsSinceEpoch}';
    final text = 'Message arrivé pendant ta commande : remplace ta réponse finale par $marker, uniquement.';
    final response = await client.request('run.steer', {'run': run.runId, 'text': text}) as Map;
    stdout.writeln('${provider.name}: steering=${response['outcome']}');
    if (response['outcome'] != 'injected') throw StateError('Le message n’a pas rejoint le tour en cours.');
    await done.timeout(const Duration(seconds: 90));
    final users = run.log.items.whereType<UserItem>().where((u) => u.text == text).toList();
    final answer = run.log.items.whereType<AgentItem>().where((a) => !a.thought).last.text;
    if (users.length != 1 || !users.single.queued || !answer.contains(marker) || run.log.working) {
      throw StateError('${provider.name}: fil ou réponse incorrect : users=${users.length}, réponse=$answer');
    }
    stdout.writeln('${provider.name}: PASS, réponse=$answer, message unique, tour terminé.');
    return true;
  } catch (error) {
    stdout.writeln('${provider.name}: FAIL $error');
    return false;
  } finally {
    await run?.stop();
    if (session != null) await _deleteSession(provider, session);
  }
}

Future<void> _deleteSession(AgentProvider provider, String id) async {
  final home = Platform.environment['USERPROFILE']!;
  final root = Directory('$home/${provider == AgentProvider.claude ? '.claude/projects' : '.codex/sessions'}');
  var deleted = 0;
  if (await root.exists()) {
    await for (final item in root.list(recursive: true, followLinks: false)) {
      if (item is! File) continue;
      final name = item.uri.pathSegments.last;
      if (name != '$id.jsonl' && !(provider == AgentProvider.codex && name.endsWith('-$id.jsonl'))) continue;
      await item.delete();
      deleted++;
    }
  }
  stdout.writeln('${provider.name}: nettoyage session=$id, fichiers supprimés=$deleted');
}
