import 'dart:convert';
import 'dart:io';

import 'package:mikky_engine/mikky_engine.dart';

/// Lines of a recorded fixture (A0 probe, 2026-09-29), JSON-decoded.
List<Map<String, dynamic>> fixture(String name) => File('test/fixtures/$name')
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty)
    .map((l) => (jsonDecode(l) as Map).cast<String, dynamic>())
    .toList();

/// Time of the recording start, to date ACP events (the stream has none).
final acpStart = DateTime.utc(2026, 9, 29, 12);

/// Replays an ACP recording into a log. [until]: stop when it returns true
/// after applying a line.
SessionLog replayAcp(String name, {bool Function(SessionLog, Map<String, dynamic>)? until}) {
  final reader = AcpReader();
  final log = SessionLog();
  for (final line in fixture('acp/$name')) {
    final at = acpStart.add(Duration(milliseconds: line['t'] as int));
    log.applyAll(reader.read((line['msg'] as Map).cast<String, dynamic>(), outgoing: line['dir'] == 'out', at: at));
    if (until != null && until(log, line)) break;
  }
  return log;
}

SessionLog replayClaude(String name) {
  final reader = ClaudeTranscriptReader();
  return SessionLog()..applyAll(fixture('claude/$name').expand(reader.read));
}

SessionLog replayCodex(String name) {
  final reader = CodexRolloutReader();
  return SessionLog()..applyAll(fixture('codex/$name').expand(reader.read));
}
