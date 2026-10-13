import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../island/content/brief_view.dart';
import '../ui/content/side.dart';
import '../ui/controls/buttons.dart';
import '../ui/foundation/tokens.dart';
import 'session_steps.dart';
import 'side_app.dart';

/// At the right edge, what Mikky brings when an agent needs the user
/// (2026-10-04): the request with its context ([BriefView]), Mikky at his
/// place at the top left (drawn by the island). Answering goes back to
/// the home; « Voir l'agent » opens its page.
///
/// FUNCTIONAL ONLY: no design of its own yet (plan of 2026-10-05).
class BriefPage extends StatelessWidget {
  const BriefPage({super.key, required this.host, required this.id, required this.back, required this.openAgent});

  final SideHost host;
  final String id;
  final VoidCallback back;
  final VoidCallback openAgent;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final source = host.service.source;
    final e = source.entry(id);
    final agent = source.agentOf(id);
    final waiting = source.agents.where((a) => a.status.needsYou).length;
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 68, 18, 18),
            child: e == null || agent == null
                ? Text('Plus rien à décider', style: uiText(TextSize.small, color: ui.text3))
                : BriefView(
                    key: ValueKey('$id:${agent.status.name}'),
                    agent: agent,
                    brief: briefOf(e.log, agent.status),
                    question: e.log.question,
                    canAlways: canAlways(e.log),
                    queue: waiting,
                    actions: BriefActions(
                      answer: (a) {
                        host.answer(id, a);
                        back();
                      },
                      answerQuestion: source.canAnswerQuestion(id)
                          ? (answers) {
                              source.answerQuestion(id, answers);
                              back();
                            }
                          : null,
                      open: openAgent,
                      reveal: () => host.service.revealOrOpen(id, openAgent),
                      // Claude's own question in its terminal instead.
                      terminal: !source.canLeaveInTerminal(id)
                          ? null
                          : () {
                              host.answer(id, AgentAnswer.dismiss);
                              back();
                            },
                    ),
                  ),
          ),
        ),
        // Mikky is the island's, at the top left (see IslandMetrics).
        SideHead(
          leading: const SizedBox(width: 56),
          title: 'Pour toi',
          small: true,
          actions: [RoundButton('x', size: 34, onPressed: back, tooltip: 'Fermer')],
        ),
      ],
    );
  }
}
