// Maintenance commands for a local backend. Never prints its credential.
import 'dart:convert';

import 'package:mikky_agents/mikky_agents.dart';

Future<void> main(List<String> args) async {
  final endpoint = DaemonEndpoint.fromCredentialStore();
  if (endpoint == null) throw StateError('No running backend');
  final client = await DaemonClient.connect(endpoint);
  try {
    final method = args.firstOrNull ?? 'hello';
    final params = args.length > 1 ? (jsonDecode(args[1]) as Map).cast<String, Object?>() : <String, Object?>{};
    print(jsonEncode(await client.request(method, params)));
  } finally {
    await client.close();
  }
}
