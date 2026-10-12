import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/enchant.dart';
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

/// What a request page needs from the island.
class RequestHost {
  const RequestHost({
    required this.requests,
    required this.entry,
    required this.answer,
    required this.answerQuestion,
    required this.later,
    required this.openAgent,
    this.reveal,
    this.finishLimit,
    this.send,
  });

  /// The requests waiting, in order ([requestQueue]); the island keeps it.
  final ValueListenable<List<Agent>> requests;

  /// The session of agent [id] (null in the demo).
  final ({SessionLog log, bool canAlways, ({String request, String? description})? hook})? Function(String id) entry;
  final void Function(String id, AgentAnswer answer) answer;
  final bool Function(String id, Map<String, Object>? answers) answerQuestion;

  /// Not now: back where the island was.
  final VoidCallback later;
  final void Function(String id) openAgent;

  /// A click on who asks (Ctrl: its terminal or VS Code).
  final void Function(String id)? reveal;
  final void Function(String id)? finishLimit;
  final Future<void> Function(String id, String text)? send;
}

/// The island goes straight to what waits (2026-10-08, « le notch va
/// droit à la demande »): the most pressing request first — questions and
/// permissions, then errors, then limits; the oldest first. « 1/3 »; once
/// answered, the next; none left, [done] (the island goes back where it
/// was).
class RequestPage extends StatefulWidget {
  const RequestPage({super.key, required this.host, required this.place, required this.done});

  final RequestHost host;
  final RequestPlace place;
  final VoidCallback done;

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  /// Answered in this round, for « 2/3 ».
  int _answered = 0;
  bool _finished = false;

  RequestHost get _host => widget.host;

  @override
  void initState() {
    super.initState();
    _host.requests.addListener(_changed);
  }

  @override
  void dispose() {
    _host.requests.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_host.requests.value.isEmpty && !_finished) {
      _finished = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.done();
      });
    }
  }

  void _did(VoidCallback action) {
    setState(() => _answered++);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final queue = _host.requests.value;
    final agent = queue.firstOrNull;
    final e = agent == null ? null : _host.entry(agent.id);
    final hook = e?.hook;
    TaskBrief? brief;
    if (agent != null) {
      brief = e == null ? briefOfAgent(agent) : briefOf(e.log, agent.status);
      if (hook != null) brief = brief.withRequest(hook.request, title: hook.description);
    }
    final id = agent?.id ?? '';
    final log = e?.log;
    return RequestView(
      place: widget.place,
      agent: agent,
      brief: brief,
      question: hook == null ? log?.question : null,
      canAlways: hook == null && (e?.canAlways ?? false),
      position: _answered + 1,
      total: _answered + queue.length,
      close: _host.later,
      actions: BriefActions(
        answer: (a) => _did(() => _host.answer(id, a)),
        answerQuestion: (answers) => _did(() => _host.answerQuestion(id, answers)),
        open: () => _host.openAgent(id),
        reveal: _host.reveal == null ? null : () => _host.reveal!(id),
        later: _host.later,
        // Claude's own question in its terminal instead.
        terminal: hook == null ? null : () => _did(() => _host.answer(id, AgentAnswer.dismiss)),
        finishLimit: agent?.status == AgentStatus.rateLimited && _host.finishLimit != null
            ? () => _did(() => _host.finishLimit!(id))
            : null,
        enchant: agent?.status == AgentStatus.rateLimited && _host.send != null && log != null
            ? () => _did(() => Enchantments.instance.enchant(id, log.limitResetsAt, (text) => _host.send!(id, text)))
            : null,
      ),
    );
  }
}
