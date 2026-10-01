import 'dart:async';
import 'dart:convert';

/// A pretend ACP agent adapter, for tests: answers like `claude-agent-acp`
/// did in the A0 probe, driven by the prompt's text:
/// - `write`: edits a file after a permission request (yes: done, no: failed);
/// - `slow`: runs until `session/cancel`;
/// - `crash`: the agent dies;
/// - `limit`: an error answer about the usage limit;
/// - anything else: answers « ok ».
class FakeAgent {
  /// The option chosen for the last permission request.
  String? lastPermission;

  FakeAgent(Stream<List<int>> input, this._output, {this.autoFallback = false}) {
    input.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine, onDone: () => closed = true);
  }

  /// In memory: [clientInput] / [clientOutput] go to the client.
  factory FakeAgent.inMemory({bool autoFallback = false}) {
    final toAgent = StreamController<List<int>>();
    final fromAgent = StreamController<List<int>>();
    final agent = FakeAgent(toAgent.stream, fromAgent.sink, autoFallback: autoFallback);
    agent.clientInput = fromAgent.stream;
    agent.clientOutput = toAgent.sink;
    return agent;
  }

  final StreamSink<List<int>> _output;

  /// Like Claude with Haiku: asked for `auto`, it switches to `acceptEdits`.
  final bool autoFallback;

  late Stream<List<int>> clientInput;
  late StreamSink<List<int>> clientOutput;

  /// Methods received, in order.
  final List<String> received = [];
  bool closed = false;

  final Map<Object, Completer<Map>> _asked = {};
  Completer<void>? _slow;
  int _nextAsk = 100;
  static const sessionId = 'fake-session-1';

  void _send(Map<String, dynamic> msg) {
    if (closed) return;
    _output.add(utf8.encode('${jsonEncode({'jsonrpc': '2.0', ...msg})}\n'));
  }

  void _update(Map<String, dynamic> update) => _send({
    'method': 'session/update',
    'params': {'sessionId': sessionId, 'update': update},
  });

  Future<void> _onLine(String line) async {
    final msg = jsonDecode(line) as Map<String, dynamic>;
    final method = msg['method'] as String?;
    final id = msg['id'];
    if (method == null) {
      _asked.remove(id)?.complete(msg);
      return;
    }
    received.add(method);
    final params = (msg['params'] as Map?) ?? const {};
    switch (method) {
      case 'initialize':
        _send({
          'id': id,
          'result': {
            'protocolVersion': 1,
            'agentCapabilities': {'loadSession': true},
          },
        });
      case 'session/new':
        _send({'id': id, 'result': _session()});
      case 'session/load':
        _update({
          'sessionUpdate': 'user_message_chunk',
          'messageId': 'u0',
          'content': {'type': 'text', 'text': 'Avant'},
        });
        _update({
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'a0',
          'content': {'type': 'text', 'text': 'Déjà fait.'},
        });
        _send({'id': id, 'result': _session()});
      case 'session/set_mode':
        if (params['modeId'] == 'auto' && autoFallback) {
          _update({'sessionUpdate': 'current_mode_update', 'currentModeId': 'acceptEdits'});
        }
        _send({'id': id, 'result': {}});
      case 'session/set_model':
        _send({'id': id, 'result': {}});
      case 'session/cancel':
        final slow = _slow;
        _slow = null;
        if (slow != null && !slow.isCompleted) slow.complete();
      case 'session/prompt':
        await _prompt(id as Object, (params['prompt'] as List).first['text'] as String);
      default:
        _send({
          'id': id,
          'error': {'code': -32601, 'message': 'Method not found'},
        });
    }
  }

  Map<String, dynamic> _session() => {
    'sessionId': sessionId,
    'modes': {
      'currentModeId': 'default',
      'availableModes': [
        {'id': 'default', 'name': 'Manual'},
        {'id': 'acceptEdits', 'name': 'Accept edits'},
        {'id': 'auto', 'name': 'Auto'},
      ],
    },
    'models': {
      'currentModelId': 'opus',
      'availableModels': [
        {'modelId': 'opus', 'name': 'Opus'},
        {'modelId': 'haiku', 'name': 'Haiku'},
      ],
    },
  };

  Future<void> _prompt(Object id, String text) async {
    switch (text) {
      case 'write':
        _update({
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'm1',
          'content': {'type': 'text', 'text': 'Je crée le fichier.'},
        });
        _update({
          'sessionUpdate': 'plan',
          'entries': [
            {'content': 'Créer a.txt', 'status': 'in_progress'},
          ],
        });
        _update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 't1',
          'title': 'Write a.txt',
          'kind': 'edit',
          'status': 'pending',
          'rawInput': {'file_path': 'a.txt', 'content': 'un'},
        });
        final askId = _nextAsk++;
        final answer = Completer<Map>();
        _asked[askId] = answer;
        _send({
          'id': askId,
          'method': 'session/request_permission',
          'params': {
            'sessionId': sessionId,
            'toolCall': {'toolCallId': 't1', 'title': 'Write a.txt'},
            'options': [
              {'optionId': 'allow-once', 'name': 'Allow', 'kind': 'allow_once'},
              {'optionId': 'allow-always', 'name': 'Always allow', 'kind': 'allow_always'},
              {'optionId': 'reject', 'name': 'Reject', 'kind': 'reject_once'},
            ],
          },
        });
        final reply = await answer.future;
        final outcome = (reply['result'] as Map)['outcome'] as Map;
        final allowed = outcome['optionId'] == 'allow-once' || outcome['optionId'] == 'allow-always';
        lastPermission = outcome['optionId'] as String?;
        if (outcome['outcome'] == 'cancelled') {
          _send({
            'id': id,
            'result': {'stopReason': 'cancelled'},
          });
          return;
        }
        _update({'sessionUpdate': 'tool_call_update', 'toolCallId': 't1', 'status': allowed ? 'completed' : 'failed'});
        _update({
          'sessionUpdate': 'plan',
          'entries': [
            {'content': 'Créer a.txt', 'status': 'completed'},
          ],
        });
        _update({'sessionUpdate': 'session_info_update', 'title': 'Créer a.txt'});
        _send({
          'id': id,
          'result': {'stopReason': 'end_turn'},
        });
      case 'ask':
        // Claude's question tool, as claude-agent-acp sends it.
        final askId = _nextAsk++;
        final answer = Completer<Map>();
        _asked[askId] = answer;
        _send({
          'id': askId,
          'method': 'elicitation/create',
          'params': {
            'mode': 'form',
            'sessionId': sessionId,
            'message': 'Quelle base ?',
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'question_0': {
                  'type': 'string',
                  'oneOf': [
                    {'const': 'SQLite', 'title': 'SQLite'},
                    {'const': 'Postgres', 'title': 'Postgres'},
                  ],
                },
                'question_0_custom': {'type': 'string'},
              },
            },
          },
        });
        final reply = (await answer.future)['result'] as Map;
        final chosen = (reply['content'] as Map?)?['question_0'] ?? reply['action'];
        _update({
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'm3',
          'content': {'type': 'text', 'text': 'Choix : $chosen'},
        });
        _send({
          'id': id,
          'result': {'stopReason': 'end_turn'},
        });
      case 'slow':
        _update({'sessionUpdate': 'tool_call', 'toolCallId': 't2', 'title': 'npm test', 'kind': 'execute', 'status': 'in_progress'});
        _slow = Completer<void>();
        await _slow!.future;
        _send({
          'id': id,
          'result': {'stopReason': 'cancelled'},
        });
      case 'crash':
        closed = true;
        await _output.close();
      case 'limit':
        _send({
          'id': id,
          'error': {'code': -32000, 'message': 'Usage limit reached, resets at 5pm'},
        });
      default:
        _update({
          'sessionUpdate': 'agent_message_chunk',
          'messageId': 'm2',
          'content': {'type': 'text', 'text': 'ok'},
        });
        _send({
          'id': id,
          'result': {'stopReason': 'end_turn'},
        });
    }
  }
}
