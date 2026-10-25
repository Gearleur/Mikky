import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/brand/app_glyph.dart';
import '../ui/brand/brand_logo.dart';
import '../ui/content/request_content.dart';
import '../ui/controls/buttons.dart';
import '../ui/foundation/tokens.dart';
import 'question_card.dart';
import 'session_views.dart';

/// The conversation and its pending form share a reading surface. Identity
/// and actions stay visible while the user reads context or answers.
class QuestionConversation extends StatefulWidget {
  const QuestionConversation({
    super.key,
    required this.name,
    required this.log,
    required this.onLater,
    required this.onOpen,
    this.provider,
    this.app,
    this.onAnswer,
    this.onReveal,
    this.draft,
    this.onContinue,
  });

  final String name;
  final SessionLog log;
  final AgentProvider? provider;
  final AgentApp? app;
  final VoidCallback onLater, onOpen;
  final VoidCallback? onReveal;
  final ValueChanged<Map<String, Object>?>? onAnswer;
  final QuestionDraft? draft;
  final VoidCallback? onContinue;

  @override
  State<QuestionConversation> createState() => _QuestionConversationState();
}

class _QuestionConversationState extends State<QuestionConversation> {
  final _scroll = RequestScrollController();
  final _question = GlobalKey();
  final _thread = ThreadCache();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toQuestion() {
    revealRequest(_question, _scroll, animate: true);
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final app = widget.app ?? widget.log.app;
    final brand = widget.provider == null ? null : Brand.of(widget.provider!);
    final source = [
      if (brand != null) brand.label,
      if (app != null && app.label != brand?.label) app.label,
    ].join(' · ');
    final history = threadOf(context, widget.log, cache: _thread);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RoundButton('left', size: 32, tooltip: 'Retour à l’accueil', onPressed: widget.onLater),
            const SizedBox(width: 10),
            if (brand != null) BrandLogo(brand, size: 22) else if (app != null) AppGlyph(app, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.isEmpty
                        ? 'Question de cet agent'
                        : '$source · ${widget.onContinue == null ? 'Question en attente' : 'Demande suivante'}',
                    style: uiText(TextSize.caption, color: ui.text2),
                  ),
                  GestureDetector(
                    onTap: widget.onOpen,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        widget.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: uiText(TextSize.body, weight: FontWeight.w600, color: ui.text),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            MButton(
              'Contexte',
              small: true,
              kind: ButtonKind.ghost,
              onPressed: history.isEmpty
                  ? null
                  : () => _scroll.animateTo(0, duration: const Duration(milliseconds: 180), curve: Curves.easeOut),
            ),
            MButton('Question', small: true, kind: ButtonKind.ghost, onPressed: _toQuestion),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: QuestionCard(
            question: widget.log.question!,
            draft: widget.draft,
            onAnswer: widget.onAnswer,
            onLater: widget.onLater,
            fill: true,
            scroll: _scroll,
            contentAnchor: _question,
            before: history.isEmpty
                ? const []
                : [
                    Text('Conversation', style: uiText(TextSize.caption, color: ui.text3)),
                    const SizedBox(height: 10),
                    ...history,
                  ],
            elsewhere: [
              ('Plus tard', widget.onLater),
              if (widget.onContinue != null)
                ('Répondre à cet agent', widget.onContinue!)
              else
                ('Ouvrir l’app', widget.onReveal ?? widget.onOpen),
            ],
            onElsewhere: widget.onContinue == null ? widget.onReveal ?? widget.onOpen : null,
          ),
        ),
      ],
    );
  }
}
