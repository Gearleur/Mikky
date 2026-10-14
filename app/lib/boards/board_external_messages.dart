import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/content/message_delivery.dart';
import '../ui/content/side.dart';
import '../ui/controls/buttons.dart';
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
    BoardSection(
      title: 'États des messages — proposition commune',
      kind: FrameKind.trial,
      note: 'La même bulle pour Claude et Codex. « Envoyé » confirme la transmission, pas la lecture. « Après ce tour » est réservé à un repli réellement annoncé. Une connexion rompue reste « Envoi non confirmé » ; seul un refus certain propose Réessayer. Ces états restent à valider avant leur branchement dans l’app.',
      frames: [
        for (final state in MessageDeliveryState.values)
          BoardFrame(
            label: state.label,
            child: SideFrame(
              height: 180,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: MessageDelivery(text: text, state: state, onRetry: () {}),
              ),
            ),
          ),
      ],
    ),
    const BoardSection(
      title: 'Réessayer — parcours interactif',
      kind: FrameKind.play,
      note: 'Cliquer Réessayer : Envoi… puis Envoyé, dans la même bulle. L’action disparaît pendant l’envoi. Rejouer remet l’échec. Démonstration locale, aucun message envoyé à un agent.',
      frames: [BoardFrame(label: 'Échec → Envoi… → Envoyé', child: MessageRetryTrial())],
    ),
  ];
});

/// Local state for the retry trial; no transport or agent is involved.
class MessageRetryTrial extends StatefulWidget {
  const MessageRetryTrial({super.key});

  @override
  State<MessageRetryTrial> createState() => _MessageRetryTrialState();
}

class _MessageRetryTrialState extends State<MessageRetryTrial> {
  var _state = MessageDeliveryState.failed;

  Future<void> _retry() async {
    if (_state != MessageDeliveryState.failed) return;
    setState(() => _state = MessageDeliveryState.sending);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _state = MessageDeliveryState.sent);
  }

  @override
  Widget build(BuildContext context) => SideFrame(
    height: 240,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MessageDelivery(text: 'Ajoute aussi un test pour ce cas.', state: _state, onRetry: _retry),
          const Spacer(),
          MButton(
            'Rejouer l’échec',
            small: true,
            kind: ButtonKind.ghost,
            onPressed: _state == MessageDeliveryState.sending
                ? null
                : () => setState(() => _state = MessageDeliveryState.failed),
          ),
        ],
      ),
    ),
  );
}
