import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../side/question_card.dart';
import '../side/request_keys.dart';
import '../ui/content/cards.dart';
import '../ui/content/request_content.dart';
import '../ui/foundation/tokens.dart';

/// The request beside Mikky, using the shared request components at the
/// same scale as the home controls.
class NotchRequest extends StatefulWidget {
  const NotchRequest({
    super.key,
    required this.name,
    required this.log,
    required this.onLater,
    required this.onOpen,
    this.onAnswer,
    this.onAnswerQuestion,
    this.onReveal,
  });

  final String name;
  final SessionLog log;
  final VoidCallback onLater, onOpen;
  final ValueChanged<AgentAnswer>? onAnswer;
  final ValueChanged<Map<String, Object>?>? onAnswerQuestion;
  final VoidCallback? onReveal;

  bool get isQuestion => log.question != null;

  @override
  State<NotchRequest> createState() => _NotchRequestState();
}

class _NotchRequestState extends State<NotchRequest> {
  final _keys = RequestKeys();

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus?.context;
    if (primary?.findAncestorWidgetOfExactType<EditableText>() != null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyP) {
      widget.onLater();
      return KeyEventResult.handled;
    }
    if (widget.isQuestion) {
      final requestKey = switch (key) {
        LogicalKeyboardKey.digit1 => RequestKey.choice1,
        LogicalKeyboardKey.digit2 => RequestKey.choice2,
        LogicalKeyboardKey.digit3 => RequestKey.choice3,
        LogicalKeyboardKey.digit4 => RequestKey.choice4,
        LogicalKeyboardKey.enter => RequestKey.enter,
        _ => null,
      };
      if (requestKey != null && _keys.send(requestKey)) return KeyEventResult.handled;
    } else if (widget.onAnswer != null) {
      if (key == LogicalKeyboardKey.keyO || key == LogicalKeyboardKey.keyY || key == LogicalKeyboardKey.enter) {
        widget.onAnswer!(AgentAnswer.allow);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyN) {
        widget.onAnswer!(AgentAnswer.deny);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _key,
    child: RequestKeysScope(keys: _keys, child: _body(context)),
  );

  Widget _body(BuildContext context) {
    final question = widget.log.question;
    if (question != null) {
      return QuestionCard(
        question: question,
        onAnswer: widget.onAnswerQuestion,
        onLater: widget.onLater,
        fill: true,
        compact: true,
        elsewhere: [('Plus tard', widget.onLater), ('Ouvrir l’app', widget.onReveal ?? widget.onOpen)],
        onElsewhere: widget.onReveal ?? widget.onOpen,
      );
    }
    final ui = MikkyUi.of(context);
    final request = widget.log.pending.firstOrNull;
    return RequestContent(
      fill: true,
      compact: true,
      actions: Align(
        alignment: Alignment.centerRight,
        child: AnswerBar(
          compact: true,
          answers: [
            ('Plus tard', widget.onLater),
            if (widget.onAnswer != null) ...[
              ('Non', () => widget.onAnswer!(AgentAnswer.deny)),
              ('Oui', () => widget.onAnswer!(AgentAnswer.allow)),
            ] else
              ('Ouvrir l’app', widget.onReveal ?? widget.onOpen),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: widget.onOpen,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                widget.name,
                style: uiText(TextSize.small, color: ui.text, weight: FontWeight.w600),
              ),
            ),
          ),
          if (request?.description case final description? when description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(description, style: uiText(TextSize.caption, color: ui.text2)),
          ],
          const SizedBox(height: 4),
          CodePill(widget.log.requestText, maxLines: null, compact: true),
        ],
      ),
    );
  }
}
