import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../island/content/brief_view.dart';
import '../ui/content/side.dart';
import '../ui/controls/buttons.dart';
import '../ui/foundation/tokens.dart';
import 'question_card.dart';

/// How a request page lays itself out: in the notch, Mikky on its left
/// (the island draws him there), the request beside him; at the right
/// edge, Mikky at the top left, « Pour toi », the request under it.
enum RequestPlace { top, right }

/// One request on screen, as the request page shows it: who asks and why
/// ([BriefView]), « 2/3 » in this round. The same view in the app and on
/// the boards.
class RequestView extends StatelessWidget {
  const RequestView({
    super.key,
    required this.place,
    required this.agent,
    required this.brief,
    required this.actions,
    this.question,
    this.canAlways = false,
    this.position = 1,
    this.total = 1,
    this.close,
    this.questionTrial = const QuestionTrial(),
    this.trial = true,
  });

  final RequestPlace place;
  final Agent? agent;
  final TaskBrief? brief;
  final BriefActions actions;
  final QuestionAsked? question;
  final bool canAlways;
  final int position, total;

  /// The × at the right edge (« Plus tard »).
  final VoidCallback? close;

  /// The question card's look and how it starts (the boards).
  final QuestionTrial questionTrial;

  /// The look of 2026-10-08 ([BriefView.trial]); off: today's, to compare.
  final bool trial;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final a = agent, b = brief;
    final Widget body = a == null || b == null
        ? Text('Plus rien à décider', style: uiText(TextSize.small, color: ui.text3))
        : BriefView(
            key: ValueKey('${a.id}:${a.status.name}'),
            agent: a,
            brief: b,
            question: question,
            canAlways: canAlways,
            queue: total,
            position: position,
            actions: actions,
            questionTrial: questionTrial,
            trial: trial,
          );
    return switch (place) {
      // In the notch: Mikky on the left, 104 px; the request beside him.
      // The trial lays itself out in the height it gets (the answers stay
      // in sight); today's look scrolls whole.
      RequestPlace.top => Padding(
        padding: const EdgeInsets.fromLTRB(104, 16, 18, 10),
        child: trial ? body : SingleChildScrollView(child: body),
      ),
      RequestPlace.right => Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 68, 18, 18),
              child: trial ? body : SingleChildScrollView(child: body),
            ),
          ),
          // Mikky is the island's, at the top left (see IslandMetrics).
          SideHead(
            leading: const SizedBox(width: 56),
            title: 'Pour toi',
            small: true,
            actions: [if (close != null) RoundButton('x', size: 34, onPressed: close, tooltip: 'Plus tard')],
          ),
        ],
      ),
    };
  }
}
