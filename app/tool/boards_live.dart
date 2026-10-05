// The boards, live (user, 2026-10-05): runs them in debug and reloads them
// (hot reload) each time a file of the app or of its packages is saved, so
// a change shows in a second, without building a bundle. For the design
// sessions. Started by `Start-Mikky.ps1 -Boards -Live`; Ctrl + C stops it.
//
//   C:\dev\flutter\bin\dart.bat tool\boards_live.dart   (in app\)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final app = File.fromUri(Platform.script).parent.parent;
  final root = app.parent;
  final flutter = Platform.environment['MIKKY_FLUTTER'] ?? r'C:\dev\flutter\bin\flutter.bat';
  stdout.writeln('Planches en direct : compilation (la première fois, une à deux minutes)…');
  final run = await Process.start(
    flutter,
    ['run', '--machine', '-d', 'windows', '--dart-entrypoint-args=--kit'],
    workingDirectory: app.path,
    runInShell: true,
  );

  String? appId;
  var started = false;
  var nextId = 1;
  var reloading = false, again = false;

  void reload() {
    // Not before the window is up: the device refuses it.
    if (appId == null || !started) return;
    if (reloading) {
      again = true;
      return;
    }
    reloading = true;
    again = false;
    final request = {'id': nextId++, 'method': 'app.restart', 'params': {'appId': appId, 'fullRestart': false, 'pause': false}};
    run.stdin.writeln(jsonEncode([request]));
  }

  // The machine protocol: one JSON list per line; anything else is said as is.
  run.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    // The engine's own lines may start with « [ » too ([IMPORTANT:…]).
    Object? messages;
    if (line.startsWith('[{')) {
      try {
        messages = jsonDecode(line);
      } on FormatException {
        messages = null;
      }
    }
    if (messages is! List) {
      if (line.trim().isNotEmpty) stdout.writeln(line);
      return;
    }
    for (final message in messages) {
      final m = message as Map;
      final params = (m['params'] as Map?) ?? const {};
      switch (m['event']) {
        case 'app.start':
          appId = params['appId'] as String?;
        case 'app.started':
          started = true;
          stdout.writeln('Planches ouvertes. Chaque fichier enregistré les recharge.');
        case 'app.log':
          stdout.writeln(params['log']);
        case 'app.stop':
          stdout.writeln('Planches fermées.');
      }
      if (m.containsKey('id') && (m.containsKey('result') || m.containsKey('error'))) {
        reloading = false;
        final result = m['result'];
        final ok = m.containsKey('result') && (result is! Map || result['code'] == 0);
        stdout.writeln(ok ? 'Rechargé.' : 'Rechargement refusé : ${m['error'] ?? (result as Map)['message']}');
        if (again) reload();
      }
    }
  });
  run.stderr.transform(utf8.decoder).listen(stderr.write);

  // Saved code, here or in the packages: reload once the saving is over.
  Timer? settle;
  for (final dir in [Directory('${app.path}/lib'), Directory('${root.path}/packages/mikky_engine/lib'), Directory('${root.path}/packages/mikky_agents/lib')]) {
    if (!dir.existsSync()) continue;
    dir.watch(recursive: true).where((e) => e.path.endsWith('.dart')).listen((_) {
      settle?.cancel();
      settle = Timer(const Duration(milliseconds: 350), reload);
    });
  }

  ProcessSignal.sigint.watch().listen((_) {
    run.stdin.writeln(jsonEncode([
      {'id': nextId++, 'method': 'app.stop', 'params': {'appId': appId}},
    ]));
  });
  exit(await run.exitCode);
}
