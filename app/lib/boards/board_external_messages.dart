import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'board_screens.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

final externalMessagesBoard = BoardSpec('Écrire pendant', 'Claude lancé dans VS Code ou un terminal', (context) {
  const text = 'Ajoute aussi un test pour ce cas.';
  final waiting = ExternalMessage(id: 'mikky-board', sessionId: 's', text: text, at: DateTime(2026));
  final delivered = FakeSessions.workingNoPlan()
    ..apply(const UserMessage(text, queued: true, messageId: 'mikky-board'));
  return [
    BoardSection(
      title: 'Écrire pendant le travail',
      kind: FrameKind.trial,
      note: 'Le champ reste disponible. Le message attend un outil ou la fin du tour ; son écho dans la session remplace la bulle en attente, sans doublon. Hooks Claude requis.',
      frames: [
        BoardFrame(
          label: 'En attente du prochain outil',
          child: AgentMock(
            title: 'Claude dans VS Code',
            log: FakeSessions.workingNoPlan(),
            external: true,
            canQueueExternal: true,
            messages: [waiting],
          ),
        ),
        BoardFrame(
          label: 'Transmis à Claude',
          child: AgentMock(title: 'Claude dans un terminal', log: delivered, external: true, canQueueExternal: true),
        ),
      ],
    ),
  ];
});
