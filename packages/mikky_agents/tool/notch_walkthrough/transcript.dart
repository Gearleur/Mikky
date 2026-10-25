import 'dart:convert';
import 'dart:io';

/// Synthetic input for the real file watcher. Its own folder and every title
/// identify it as a visual test; it never executes the tools it describes.
class WalkthroughTranscript {
  WalkthroughTranscript(this.folder, this.id, {this.codex = false});

  final Directory folder;
  final String id;
  final bool codex;
  int _sequence = 0;
  File get file => File('${folder.path}/${codex ? 'rollout-' : ''}$id.jsonl');
  String get apiPath => file.absolute.path.replaceAll('/', Platform.pathSeparator);

  Future<void> write(Map<String, Object?> row) async {
    await folder.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        if (!codex) ...{'sessionId': id, 'cwd': folder.path, 'entrypoint': 'desktop', 'uuid': '$id-${_sequence++}'},
        ...row,
      })}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> begin(String prompt) async {
    if (codex) {
      await write({
        'type': 'session_meta',
        'payload': {'id': id, 'cwd': folder.path, 'originator': 'codex_desktop'},
      });
      await event('task_started');
      await event('user_message', {'message': prompt});
    } else {
      await write({
        'type': 'user',
        'message': {'content': prompt},
      });
      await write({'type': 'custom-title', 'customTitle': 'TEST NOTCH · Atelier des questions'});
    }
  }

  Future<void> event(String type, [Map<String, Object?> data = const {}]) => write({
    'type': 'event_msg',
    'payload': {'type': type, ...data},
  });

  Future<void> say(String text, {bool end = false}) async {
    if (codex) {
      await event('agent_message', {'message': text});
      if (end) await event('task_complete');
    } else {
      await write({
        'type': 'assistant',
        'message': {
          'id': '$id-message-${_sequence++}',
          'content': [
            {'type': 'text', 'text': text},
          ],
          'stop_reason': end ? 'end_turn' : null,
        },
      });
    }
  }

  Future<void> tool(String toolId, String name, Map<String, Object?> input) => write({
    'type': 'assistant',
    'message': {
      'id': '$id-tool-${_sequence++}',
      'content': [
        {'type': 'tool_use', 'id': toolId, 'name': name, 'input': input},
      ],
      'stop_reason': 'tool_use',
    },
  });

  Future<void> result(String toolId, Object result, {bool denied = false}) => write({
    'type': 'user',
    'message': {
      'content': [
        {'type': 'tool_result', 'tool_use_id': toolId, 'content': jsonEncode(result), 'is_error': denied},
      ],
    },
  });

  Future<void> limit() => write({
    'type': 'assistant',
    'error': 'rate_limit',
    'isApiErrorMessage': true,
    'apiErrorStatus': 429,
    'quotaLimits': {'resetsAt': DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch ~/ 1000},
    'message': {
      'id': '$id-limit',
      'content': [
        {'type': 'text', 'text': 'TEST NOTCH : limite simulée, aucune limite réelle de compte.'},
      ],
    },
  });

  Future<void> resume() => write({
    'type': 'user',
    'message': {'content': 'TEST NOTCH : je reprends dans mon application.'},
  });
}
