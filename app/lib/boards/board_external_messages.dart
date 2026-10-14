import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'board_screens.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

final externalMessagesBoard = BoardSpec('Écrire pendant', 'Claude ou Codex lancé dans VS Code ou un terminal', (
  context,
) {
  const text = 'Ajoute aussi un test pour ce cas.';
  final waiting = ExternalMessage(id: 'mikky-board', sessionId: 's', text: text, at: DateTime(2026));
  final delivered = FakeSessions.workingNoPlan()
    ..apply(const UserMessage(text, queued: true, messageId: 'mikky-board'));
  return [
    BoardSection(
      title: 'Écrire pendant le travail',
      kind: FrameKind.trial,
      note: 'Le champ reste disponible. Le message attend un outil ou la fin du tour ; son écho dans la session remplace la bulle en attente, sans doublon. Hooks du fournisseur requis.',
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
        BoardFrame(
          label: 'Codex — en attente du prochain outil',
          child: AgentMock(
            title: 'Codex dans VS Code',
            log: FakeSessions.workingNoPlan(),
            external: true,
            canQueueExternal: true,
            messages: [
              ExternalMessage(id: 'mikky-codex-board', sessionId: 's', text: text, at: DateTime(2026), agent: 'codex'),
            ],
          ),
        ),
        BoardFrame(
          label: 'Transmis à Codex',
          child: AgentMock(
            title: 'Codex dans un terminal',
            log: FakeSessions.workingNoPlan(),
            external: true,
            canQueueExternal: true,
            messages: [
              ExternalMessage(
                id: 'mikky-codex-board',
                sessionId: 's',
                text: text,
                at: DateTime(2026),
                agent: 'codex',
                delivered: true,
              ),
            ],
          ),
        ),
      ],
    ),
  ];
});
