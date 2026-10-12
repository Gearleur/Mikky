import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/agents/agents_service.dart';
import 'package:mikky_agents/mikky_agents.dart';

/// What a fresh `mikkyd` answers to the calls the service makes as it
/// starts; anything else: an empty result.
Object _freshDaemon(String method) => switch (method) {
  'hello' => {'protocol': 3, 'persistent': true},
  'state.get' => {
    'agents': <String, Object?>{},
    'marks': <String, Object?>{},
    'choices': <String, Object?>{},
    'recentFolders': <Object>[],
  },
  'runs.list' || 'sessions.list' => <Object>[],
  'tools.status' => {'ready': false},
  'autostart.status' => {'enabled': false},
  _ => <String, Object>{},
};

void main() {
  test('an unavailable backend never switches to local execution', () async {
    final dir = await Directory.systemTemp.createTemp('mikky-service-');
    final file = File('${dir.path}/agents.json');
    final service = AgentsService(clock: () => 0, store: AgentStore(file), connectBackend: () async => null);
    try {
      await service.start();
      expect(service.backend, BackendState.unavailable);
      expect(service.canLaunch, isFalse);
      expect(service.keepsAgents, isTrue);
      await service.store.save();
      expect(service.store.saveError, isA<StateError>());
      expect(await file.exists(), isFalse);
    } finally {
      await service.shutdown();
      service.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('a question from the hooks: answered through hooks.answer; reveal brings its window, else VS Code', () async {
    final dir = await Directory.systemTemp.createTemp('mikky-service-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final calls = <(String, Object?)>[];
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((data) {
        final message = jsonDecode(data as String) as Map;
        final method = message['method'] as String;
        calls.add((method, message['params']));
        final Object result = switch (method) {
          'hooks.list' => [
            {
              'id': 5,
              'kind': 'question',
              'sessionId': 's-q',
              'tool': 'AskUserQuestion',
              'title': 'Quelle base ?',
              'cwd': r'C:\projet',
              'agent': 'claude',
              'questions': [
                {
                  'question': 'Quelle base ?',
                  'header': 'Base',
                  'multiSelect': false,
                  'options': [
                    {'label': 'SQLite', 'description': ''},
                    {'label': 'Postgres', 'description': ''},
                  ],
                },
              ],
            },
          ],
          'hooks.origin' => {
            'windowPid': 4242,
            'windowHandle': 99,
            'windowExe': 'WindowsTerminal.exe',
            'cwd': r'C:\projet',
          },
          'hooks.answer' => true,
          _ => _freshDaemon(method),
        };
        socket.add(jsonEncode({'jsonrpc': '2.0', 'id': message['id'], 'result': result}));
      });
    });
    final brought = <(int, int)>[];
    final opened = <List<String>>[];
    var windowThere = false;
    final service = AgentsService(
      clock: () => 0,
      store: AgentStore(File('${dir.path}/agents.json')),
      connectBackend: () => DaemonClient.connect(DaemonEndpoint(server.port, 'test')),
      bringForward: (pid, handle) async {
        brought.add((pid, handle));
        return windowThere;
      },
      openVsCode: (args) async {
        opened.add(args);
        return true;
      },
    );
    try {
      await service.start();
      String? id;
      for (var i = 0; i < 200 && id == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        id = service.source.entries.where((e) => e.sessionId == 's-q').firstOrNull?.id;
      }
      final question = service.source.questionOf(id!)!;
      expect(question.questions.single.text, 'Quelle base ?');
      expect(service.source.answerQuestion(id, {question.questions.single.key: 'Postgres'}), isTrue);
      for (var i = 0; i < 200 && !calls.any((c) => c.$1 == 'hooks.answer'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(calls.firstWhere((c) => c.$1 == 'hooks.answer').$2, {
        'id': 5,
        'answers': {'Quelle base ?': 'Postgres'},
      });

      // The window is gone: VS Code on the folder.
      expect(await service.reveal('s-q'), isTrue);
      expect(calls.lastWhere((c) => c.$1 == 'hooks.origin').$2, {'sessionId': 's-q'});
      expect(brought, [(4242, 99)]);
      expect(opened, [
        [r'C:\projet'],
      ]);
      // It is there: only the window.
      windowThere = true;
      expect(await service.reveal('s-q'), isTrue);
      expect(opened, hasLength(1));
    } finally {
      await service.shutdown();
      service.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });

  test('closing and reconnecting screens never sends an agent stop', () async {
    final dir = await Directory.systemTemp.createTemp('mikky-service-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final requests = <String>[];
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((data) {
        final message = jsonDecode(data as String) as Map;
        final method = message['method'] as String;
        requests.add(method);
        final Object result = switch (method) {
          'tools.auth' => {'installed': false, 'loggedIn': false},
          _ => _freshDaemon(method),
        };
        try {
          socket.add(jsonEncode({'jsonrpc': '2.0', 'id': message['id'], 'result': result}));
        } on StateError {
          // The test deliberately disconnects while status probes are in flight.
        }
      });
    });
    final service = AgentsService(
      clock: () => 0,
      store: AgentStore(File('${dir.path}/agents.json')),
      connectBackend: () => DaemonClient.connect(DaemonEndpoint(server.port, 'test')),
    );
    try {
      await service.start();
      expect(service.backend, BackendState.online);
      final disconnected = service.daemon!.done;
      await sockets.first.close();
      await disconnected;
      await Future<void>.delayed(Duration.zero);
      expect(service.backend, BackendState.reconnecting);
      expect(service.canLaunch, isFalse);
      await service.reconnect();
      expect(service.backend, BackendState.online);
      expect(sockets, hasLength(2));
      await service.shutdown();
      expect(requests.where((m) => m.contains('stop') || m == 'daemon.shutdown'), isEmpty);
      expect(await service.store.file.exists(), isFalse);
    } finally {
      await service.shutdown();
      service.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
