// Read-only check of the thread a session file becomes, with a private
// mikkyd (the one built in daemon/target, not the one in service):
//   dart run tool/thread_check.dart <mikkyd.exe> <session.jsonl>...
// Prints counts and the latest tools (kind, status, title); never the
// conversation itself.
import 'dart:convert';
import 'dart:io';

import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_agents/src/daemon/session_wire.dart';
import 'package:mikky_engine/mikky_engine.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) throw ArgumentError('Pass mikkyd.exe and session files');
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']!;
  final process = await Process.start(args.first, ['--stdout-endpoint', '--watch-home', home]);
  final errors = process.stderr.drain<void>();
  try {
    final line = await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first;
    final client = await DaemonClient.connect(DaemonEndpoint.parse(line)!);
    await Future<void>.delayed(const Duration(seconds: 4));
    for (final path in args.skip(1)) {
      final log = SessionLog();
      var after = 0;
      var more = true;
      while (more) {
        final page = await client.request('sessions.read', {'path': path, 'after': after}) as Map;
        for (final e in page['lines'] as List) {
          if (sessionEventFromWire((e as Map).cast<String, dynamic>()) case final event?) log.apply(event);
        }
        after = page['next'] as int;
        more = page['more'] == true;
      }
      final tools = log.items.whereType<ToolItem>().toList();
      final counts = <String, int>{};
      for (final t in tools) {
        final key = '${t.kind.name}/${t.status.name}${t.diff == null ? '' : '+diff'}';
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final agent = log.items.whereType<AgentItem>();
      print(path.split(RegExp(r'[\\/]')).last);
      print(
        '  turns ${log.turns.length}, messages ${agent.where((a) => !a.thought).length}, '
        'thoughts ${agent.where((a) => a.thought).length}, tools ${tools.length}',
      );
      print('  status ${log.statusAt(DateTime.now()).name} · ${log.detail}');
      print('  $counts');
      for (final t in tools.skip(tools.length > 12 ? tools.length - 12 : 0)) {
        final title = t.title.replaceAll(RegExp(r'\s+'), ' ');
        final diff = t.diff == null ? '' : ' [line ${t.diff!.line}]';
        print(
          '  ${t.kind.name.padRight(7)} ${t.status.name.padRight(9)} '
          '${title.length > 90 ? '${title.substring(0, 89)}…' : title}$diff',
        );
      }
    }
    await client.close();
  } finally {
    process.kill();
    await errors;
  }
}
