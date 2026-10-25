import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:test/test.dart';

void main() {
  test('closing during notification traffic ignores frames buffered after completion', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      peers.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map;
        socket.add(jsonEncode({'jsonrpc': '2.0', 'id': message['id'], 'result': true}));
        for (var i = 0; i < 200; i++) {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'sessions.changed',
              'params': {'index': i},
            }),
          );
        }
      });
    });
    try {
      for (var i = 0; i < 10; i++) {
        final client = await DaemonClient.connect(DaemonEndpoint(server.port, 'local-test'));
        var closing = false;
        var afterClosed = 0;
        final events = client.notifications.listen((_) {
          if (client.isClosed) afterClosed++;
          if (!closing) {
            closing = true;
            unawaited(client.close());
          }
        });
        await client.request('flood');
        await client.done.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(afterClosed, 0);
        await events.cancel();
      }
    } finally {
      for (final peer in peers) {
        await peer.close();
      }
      await server.close(force: true);
    }
  });
}
