// A0 probe (plan 2026-09-29): talks ACP to claude-agent-acp or codex-acp,
// on Windows or in WSL, logs every message to a .jsonl file and answers
// permission requests from a script. Not part of the app.
//
// dart run tool/acp_probe.dart --agent claude --target windows
//   --adapters <dir with node_modules> --cwd <dir> --log out.jsonl
//   [--mode <id>] [--prompt <text>] [--then <text>] [--answers allow,deny,wait:5]
//   [--steer <seconds>:<text>] [--cancel <seconds>] [--load <sessionId>]
//   [--timeout <seconds>] [--env K=V]...
import 'dart:async';
import 'dart:convert';
import 'dart:io';

late IOSink _log;
final _watch = Stopwatch()..start();
late Process _proc;
int _nextId = 0;
final _pending = <int, Completer<Map<String, dynamic>>>{};
final _answers = <String>[];
final _gotUpdates = <String, int>{};

void main(List<String> argv) async {
  final a = _parse(argv);
  final agent = a['agent']!.single;
  final target = a['target']!.single;
  final adapters = a['adapters']!.single;
  final cwd = a['cwd']!.single;
  _answers.addAll((a['answers']?.single ?? '').split(',').where((s) => s.isNotEmpty));
  _log = File(a['log']!.single).openWrite();

  final pkg = agent == 'claude' ? 'claude-agent-acp' : 'codex-acp';
  final env = <String, String>{for (final kv in a['env'] ?? const <String>[]) kv.split('=').first: kv.substring(kv.indexOf('=') + 1)};
  if (target == 'windows') {
    final script = '$adapters\\node_modules\\@agentclientprotocol\\$pkg\\dist\\index.js';
    _proc = await Process.start('node', [script], workingDirectory: cwd, environment: env);
  } else {
    final script = '$adapters/node_modules/@agentclientprotocol/$pkg/dist/index.js';
    final exports = env.entries.map((e) => "export ${e.key}='${e.value}';").join(' ');
    _proc = await Process.start('wsl.exe', [
      '-d',
      'Ubuntu',
      '--cd',
      cwd,
      '--',
      'bash',
      '-lc',
      '$exports exec \$HOME/.local/share/mikky/node/bin/node $script',
    ]);
  }
  _note('spawned pid ${_proc.pid}');

  _proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(_onLine);
  _proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((l) => _write('stderr', l));
  unawaited(_proc.exitCode.then((c) => _note('exit $c')));

  Timer(Duration(seconds: int.parse(a['timeout']?.single ?? '240')), () async {
    _note('timeout');
    await _quit(2);
  });

  final init = await _request('initialize', {
    'protocolVersion': 1,
    'clientCapabilities': {
      'fs': {'readTextFile': false, 'writeTextFile': false},
      'terminal': false,
    },
    'clientInfo': {'name': 'mikky-probe', 'version': '0.1.0'},
  });
  _note('initialize → ${_short(init)}');

  if (a.containsKey('list')) {
    final r = await _request('session/list', {if (a['list']!.single != 'all') 'cwd': cwd});
    final sessions = ((r['result'] as Map?)?['sessions'] as List?) ?? const [];
    _note(
      'session/list → ${sessions.length} sessions, first: ${_short(sessions.take(3).toList(), 900)} · keys ${_short((r['result'] as Map?)?.keys.toList())}',
    );
    if (!a.containsKey('load')) return _quit(0);
  }

  String sessionId;
  final load = a['load']?.single;
  if (load != null) {
    final r = await _request('session/load', {'sessionId': load, 'cwd': cwd, 'mcpServers': []});
    sessionId = load;
    _note('session/load → ${_short(r)} · updates so far $_gotUpdates');
  } else {
    final r = await _request('session/new', {'cwd': cwd, 'mcpServers': []});
    final res = r['result'] as Map<String, dynamic>?;
    if (res == null) return _quit(1);
    sessionId = res['sessionId'] as String;
    _note('session $sessionId · modes ${jsonEncode(res['modes'])}');
  }

  final mode = a['mode']?.single;
  if (mode != null) {
    final r = await _request('session/set_mode', {'sessionId': sessionId, 'modeId': mode});
    _note('set_mode $mode → ${_short(r)}');
  }

  final steer = a['steer']?.single;
  Future<void>? steered;
  if (steer != null) {
    final i = steer.indexOf(':');
    steered = Future<void>.delayed(Duration(seconds: int.parse(steer.substring(0, i))), () async {
      _note('steer: sending prompt during the turn');
      final r = await _prompt(sessionId, steer.substring(i + 1));
      _note('steer prompt → ${_short(r)} · updates $_gotUpdates');
    });
  }
  final cancel = a['cancel']?.single;
  if (cancel != null) {
    Timer(Duration(seconds: int.parse(cancel)), () {
      _note('cancel');
      _send({
        'jsonrpc': '2.0',
        'method': 'session/cancel',
        'params': {'sessionId': sessionId},
      });
    });
  }

  for (final text in [...?a['prompt'], ...?a['then']]) {
    final r = await _prompt(sessionId, text);
    _note('prompt → ${_short(r)} · updates $_gotUpdates');
  }
  await steered;
  await _quit(0);
}

Future<Map<String, dynamic>> _prompt(String sessionId, String text) => _request('session/prompt', {
  'sessionId': sessionId,
  'prompt': [
    {'type': 'text', 'text': text},
  ],
});

Future<void> _quit(int code) async {
  await Future<void>.delayed(const Duration(milliseconds: 300));
  _proc.kill();
  await _log.flush();
  await _log.close();
  exit(code);
}

Future<Map<String, dynamic>> _request(String method, Map<String, dynamic> params) {
  final id = _nextId++;
  final c = Completer<Map<String, dynamic>>();
  _pending[id] = c;
  _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
  return c.future;
}

void _send(Map<String, dynamic> msg) {
  _write('out', msg);
  _proc.stdin.writeln(jsonEncode(msg));
}

void _onLine(String line) {
  Map<String, dynamic> msg;
  try {
    msg = jsonDecode(line) as Map<String, dynamic>;
  } catch (_) {
    _write('stdout-text', line);
    return;
  }
  _write('in', msg);
  final method = msg['method'] as String?;
  final id = msg['id'];
  if (method == null && id is int) {
    _pending.remove(id)?.complete(msg);
    return;
  }
  if (method == 'session/update') {
    final u = (msg['params'] as Map)['update'] as Map;
    final kind = u['sessionUpdate'] as String;
    _gotUpdates[kind] = (_gotUpdates[kind] ?? 0) + 1;
    if (kind == 'tool_call' || kind == 'tool_call_update' || kind == 'plan' || kind == 'current_mode_update') {
      _note('update $kind ${_short(u, 160)}');
    }
    return;
  }
  if (method == 'session/request_permission') {
    _onPermission(msg);
    return;
  }
  if (id != null) {
    _note('unknown request $method');
    _send({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': -32601, 'message': 'not supported by the probe'},
    });
  }
}

Future<void> _onPermission(Map<String, dynamic> msg) async {
  final params = msg['params'] as Map;
  final options = (params['options'] as List).cast<Map>();
  final answer = _answers.isEmpty ? 'allow' : _answers.removeAt(0);
  _note(
    'PERMISSION asked: ${_short(params['toolCall'], 200)} · options ${options.map((o) => '${o['optionId']}/${o['kind']}').join(' ')} · answer $answer',
  );
  var kind = answer;
  if (answer.startsWith('wait:')) {
    await Future<void>.delayed(Duration(seconds: int.parse(answer.substring(5))));
    kind = 'allow';
  }
  final want = kind == 'deny' ? 'reject_once' : 'allow_once';
  final opt = options.firstWhere((o) => o['kind'] == want, orElse: () => options.first);
  _send({
    'jsonrpc': '2.0',
    'id': msg['id'],
    'result': {
      'outcome': {'outcome': 'selected', 'optionId': opt['optionId']},
    },
  });
}

void _write(String dir, Object msg) => _log.writeln(jsonEncode({'t': _watch.elapsedMilliseconds, 'dir': dir, 'msg': msg}));

void _note(String s) {
  final line = '[${(_watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $s';
  stdout.writeln(line);
  _write('note', s);
}

String _short(Object? o, [int max = 400]) {
  final s = jsonEncode(o);
  return s.length <= max ? s : '${s.substring(0, max)}…';
}

Map<String, List<String>> _parse(List<String> argv) {
  final out = <String, List<String>>{};
  for (var i = 0; i < argv.length; i += 2) {
    out.putIfAbsent(argv[i].replaceFirst('--', ''), () => []).add(argv[i + 1]);
  }
  return out;
}
