import 'dart:math';

final _messageRandom = Random.secure();

/// A user message queued in mikkyd for an external Claude or Codex session. Memory
/// only: waiting until its next hook, delivered once the relay flushed stdout.
class ExternalMessage {
  /// Unique across app windows; also used to deduplicate transcript echoes.
  static String newId() =>
      'mikky-${List.generate(4, (_) => _messageRandom.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')).join()}';

  const ExternalMessage({
    required this.id,
    required this.sessionId,
    required this.text,
    required this.at,
    this.delivered = false,
    this.agent = 'claude',
  });

  factory ExternalMessage.fromWire(Map value) => ExternalMessage(
    id: value['id'] as String,
    sessionId: value['sessionId'] as String,
    text: value['text'] as String,
    at: DateTime.parse(value['at'] as String),
    delivered: value['state'] == 'delivered',
    agent: value['agent'] as String? ?? 'claude',
  );

  final String id, sessionId, text;
  final DateTime at;
  final bool delivered;
  final String agent;
  String get label =>
      delivered ? 'Transmis à ${agent == 'codex' ? 'Codex' : 'Claude'}' : 'En attente du prochain outil';
}
