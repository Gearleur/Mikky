@TestOn('windows')
library;

import 'dart:convert';

import '../../mikky_engine/test/support/readers/acp_reader.dart';

import 'dart:io';

import 'package:mikky_agents/src/daemon/session_wire.dart';
import 'package:mikky_engine/mikky_engine.dart';
import 'package:test/test.dart';

import 'daemon_watcher_test.dart' show snapshot;

void main() {
  for (final fixture in Directory(
    '../mikky_engine/test/fixtures/acp',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl'))) {
    test('Rust ACP matches ${fixture.uri.pathSegments.last} at every message', () async {
      final process = await Process.start('../../daemon/target/debug/examples/normalize.exe', []);
      final output = process.stdout.transform(utf8.decoder).transform(const LineSplitter()).toList();
      final errors = process.stderr.transform(utf8.decoder).join();
      final lines = await fixture.readAsLines();
      for (final line in lines.where((l) => l.trim().isNotEmpty)) {
        process.stdin.writeln(line);
      }
      await process.stdin.close();
      expect(await process.exitCode, 0, reason: await errors);
      final rust = await output;
      final expected = SessionLog(), actual = SessionLog();
      final reader = AcpReader();
      final at = DateTime.utc(2026, 9, 30);
      var i = 0;
      for (final line in lines.where((l) => l.trim().isNotEmpty)) {
        final record = jsonDecode(line) as Map;
        expected.applyAll(reader.read((record['msg'] as Map).cast<String, dynamic>(), outgoing: record['dir'] == 'out', at: at));
        for (final value in jsonDecode(rust[i++]) as List) {
          final event = sessionEventFromWire((value as Map).cast<String, dynamic>());
          if (event != null) actual.apply(event);
        }
        expect(snapshot(actual), snapshot(expected), reason: 'message $i');
        expect(actual.modeId, expected.modeId, reason: 'mode at $i');
        expect(actual.modelId, expected.modelId, reason: 'model at $i');
        expect(actual.pending.length, expected.pending.length, reason: 'permissions at $i');
        expect(actual.question?.requestId, expected.question?.requestId, reason: 'question at $i');
      }
    });
  }
}
