import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../foundation/motion.dart';
import '../foundation/tokens.dart';
import 'messages.dart';

/// Presentation states tried on the boards before backend delivery is mapped.
enum MessageDeliveryState {
  sending('Envoi…'),
  sent('Envoyé'),
  waitingForTool('En attente du prochain outil'),
  afterTurn('Après ce tour'),
  failed('Échec de l’envoi'),
  unconfirmed('Envoi non confirmé');

  const MessageDeliveryState(this.label);
  final String label;
}

/// The shared user bubble with delivery feedback. A retry is offered only
/// for a known rejection; a lost acknowledgement is not proof of failure.
class MessageDelivery extends StatelessWidget {
  const MessageDelivery({super.key, required this.text, required this.state, this.onRetry});

  final String text;
  final MessageDeliveryState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChatMessage(
          me: true,
          text: text,
          meta: state.label,
          metaColor: switch (state) {
            MessageDeliveryState.failed => ui.red,
            MessageDeliveryState.unconfirmed => ui.amber,
            _ => null,
          },
        ),
        if (state == MessageDeliveryState.unconfirmed)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
            child: Text(
              'Vérifie le fil avant de renvoyer ce message.',
              textAlign: TextAlign.right,
              style: uiText(TextSize.caption, color: ui.text2, height: 1.4),
            ),
          ),
        if (state == MessageDeliveryState.failed && onRetry != null)
          FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  onRetry!();
                  return null;
                },
              ),
            },
            child: Semantics(
              excludeSemantics: true,
              button: true,
              label: 'Réessayer',
              onTap: onRetry,
              child: HoverBuilder(
                builder: (context, hover) => Pressable(
                  onTap: onRetry,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text(
                      'Réessayer',
                      style: uiText(
                        TextSize.caption,
                        color: ui.blue,
                        weight: FontWeight.w600,
                      ).copyWith(decoration: hover ? TextDecoration.underline : null),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
