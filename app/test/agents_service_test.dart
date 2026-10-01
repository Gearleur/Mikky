import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/agents/agents_service.dart';
import 'package:mikky_agents/mikky_agents.dart';

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
          'hello' => {'protocol': 3, 'persistent': true},
          'state.get' => {'agents': {}, 'marks': {}, 'choices': {}, 'recentFolders': []},
          'runs.list' || 'sessions.list' => <Object>[],
          'tools.status' => {'ready': false},
          'tools.auth' => {'installed': false, 'loggedIn': false},
          'autostart.status' => {'enabled': false},
          _ => <String, Object>{},
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
