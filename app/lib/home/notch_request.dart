import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../side/question_card.dart';
import '../side/question_conversation.dart';
import '../side/request_keys.dart';
import '../ui/brand/brand_logo.dart';
import '../ui/content/cards.dart';
import '../ui/content/request_content.dart';
import '../ui/controls/buttons.dart';
import '../ui/foundation/tokens.dart';

/// Approvals beside the apps, questions as a full form, sharing the same
/// answer handling and keyboard shortcuts.
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
    this.questionDraft,
    this.provider,
    this.app,
    this.onContinue,
  });

  final String name;
  final SessionLog log;
  final VoidCallback onLater, onOpen;
  final ValueChanged<AgentAnswer>? onAnswer;
  final ValueChanged<Map<String, Object>?>? onAnswerQuestion;
  final VoidCallback? onReveal;
  final QuestionDraft? questionDraft;
  final AgentProvider? provider;
  final AgentApp? app;

  /// Explicit handoff between two conversations, avoiding an instant switch.
  final VoidCallback? onContinue;

  @override
  State<NotchRequest> createState() => _NotchRequestState();
}

class _NotchRequestState extends State<NotchRequest> {
  final _keys = RequestKeys();

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (widget.onContinue != null) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus?.context;
    if (primary?.findAncestorWidgetOfExactType<EditableText>() != null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyP) {
      widget.onLater();
      return KeyEventResult.handled;
    }
    if (widget.log.question != null) {
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
    final ui = MikkyUi.of(context);
    if (widget.log.question != null) {
      return QuestionConversation(
        name: widget.name,
        log: widget.log,
        provider: widget.provider,
        app: widget.app,
        draft: widget.questionDraft,
        onAnswer: widget.onContinue == null ? widget.onAnswerQuestion : null,
        onContinue: widget.onContinue,
        onLater: widget.onLater,
        onOpen: widget.onOpen,
        onReveal: widget.onReveal,
      );
    }
    if (widget.onContinue != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _approvalHeading(ui),
          const SizedBox(height: 16),
          Text('Une autre conversation attend ta réponse.', style: uiText(TextSize.body, color: ui.text2)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: MButton('Lire la demande', onPressed: widget.onContinue),
          ),
        ],
      );
    }
    final request = widget.log.pending.firstOrNull;
    return RequestContent(
      fill: true,
      compact: true,
      heading: _approvalHeading(ui),
      actions: Align(
        alignment: Alignment.centerLeft,
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
          if (request?.description case final description? when description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: uiText(TextSize.caption, color: ui.text2),
            ),
          ],
          const SizedBox(height: 4),
          CodePill(widget.log.requestText, maxLines: null, compact: true),
        ],
      ),
    );
  }

  Widget _approvalHeading(MikkyUi ui) {
    final provider = widget.provider;
    final app = widget.app ?? widget.log.app;
    final name = provider == null ? null : Brand.of(provider).label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (provider != null) ...[BrandLogo(Brand.of(provider), size: 12), const SizedBox(width: 5)],
            Text(
              [?name, if (app != null && app.label != name) app.label].join(' · '),
              style: uiText(TextSize.caption, color: ui.text2),
            ),
          ],
        ),
        const SizedBox(height: 2),
        _title(ui),
      ],
    );
  }

  Widget _title(MikkyUi ui, {double size = TextSize.small}) => GestureDetector(
    onTap: widget.onOpen,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Text(
        widget.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: uiText(size, color: ui.text, weight: FontWeight.w600),
      ),
    ),
  );
}
