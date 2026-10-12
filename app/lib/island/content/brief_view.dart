import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../../side/question_card.dart';
import '../../side/request_keys.dart';
import '../../side/session_cards.dart';
import '../../ui/content/cards.dart';
import '../../ui/content/diff_view.dart';
import '../../ui/foundation/tokens.dart';

/// What the user can do from a brief.
class BriefActions {
  const BriefActions({
    required this.answer,
    this.answerQuestion,
    this.open,
    this.terminal,
    this.later,
    this.reveal,
    this.finishLimit,
    this.enchant,
  });

  /// Oui / Non / Toujours, Relancer, OK.
  final ValueChanged<AgentAnswer> answer;

  /// The answers to a question by key; null: skipped.
  final ValueChanged<Map<String, Object>?>? answerQuestion;

  /// The agent's page.
  final VoidCallback? open;

  /// Leave the request to the terminal it came from (sessions followed
  /// through Claude's hooks).
  final VoidCallback? terminal;

  /// Not now: back where the island was, the request still waiting.
  final VoidCallback? later;

  /// A click on who asks: its page; with Ctrl, its terminal or VS Code
  /// (2026-10-08). Defaults to [open].
  final VoidCallback? reveal;

  /// A limit: « Terminer » (no more waiting), « Relance auto ».
  final VoidCallback? finishLimit, enchant;
}

/// Everything about one request, as Mikky brings it (2026-10-04): who
/// asks and why, the task and its step, what the agent just said and did,
/// then the request and its answers. In a request page, it hears the
/// island's keys (2026-10-08): Y / N / T, 1 to 4, Entrée.
///
/// FUNCTIONAL ONLY: the plain components of the home, no design of its
/// own yet (to draw with the user on the boards, plan of 2026-10-05).
class BriefView extends StatelessWidget {
  const BriefView({
    super.key,
    required this.agent,
    required this.brief,
    required this.actions,
    this.question,
    this.canAlways = false,
    this.queue = 1,
    this.position = 1,
    this.questionTrial = const QuestionTrial(),
    this.trial = false,
  });

  final Agent agent;
  final TaskBrief brief;
  final BriefActions actions;

  /// A question with choices waiting for an answer.
  final QuestionAsked? question;

  /// The agent offers « Toujours ».
  final bool canAlways;

  /// Requests in this round, this one included, and which one this is
  /// (« 2/3 »).
  final int queue, position;

  /// The question card's look and how it starts (the boards).
  final QuestionTrial questionTrial;

  /// The request page of 2026-10-08, shown on the boards (Notch Top) until
  /// it goes into the island: who asks at the top, the request and its
  /// answers at the bottom, the question card filling the room, the change
  /// counted beside its file. Off, the app's look: one column, the count
  /// after the command. The question card is the same in both.
  final bool trial;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final b = brief;
    final line = reactionTo(null, agent.status).line ?? '';
    final small = uiText(TextSize.caption, color: ui.text2, height: 1.35);
    final where = [
      ?agent.provider?.label,
      if (agent.host == AgentHost.wsl) 'WSL',
      if (agent.origin == AgentOrigin.external) 'session extérieure',
      if (agent.cwd != null) _folder(agent.cwd!),
    ].join(' · ');
    // In the trial, what the agent asks to do is the request below: not
    // twice.
    final recent = trial && b.kind == BriefKind.approval ? b.recent.where((a) => !a.running).toList() : b.recent;
    final context_ = <Widget>[
      if (b.task != null) _Labeled('Tâche', b.task!, style: small),
      if (b.step != null) _Labeled('Étape', b.step!, style: small),
      if (b.said != null) _Labeled('Dit', '« ${b.said!} »', style: small),
      if (recent.isNotEmpty) ...[const SizedBox(height: 2), for (final a in recent) _ActivityRow(a)],
    ];

    final title = Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: agent.name,
                  style: uiText(TextSize.body, weight: FontWeight.w600, color: ui.text),
                ),
                TextSpan(
                  text: '  $line',
                  style: uiText(TextSize.small, color: ui.text2),
                ),
                // The trial: where it runs on the same line.
                if (trial && where.isNotEmpty)
                  TextSpan(
                    text: '  ·  $where',
                    style: uiText(TextSize.caption, color: ui.text3),
                  ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (queue > 1) ...[
          const SizedBox(width: 8),
          Text('$position/$queue', style: uiText(TextSize.caption, color: ui.text3, tabular: true)),
        ],
      ],
    );
    // Ctrl + click on who asks: its terminal or VS Code (2026-10-08); a
    // plain click, its page.
    final head = actions.reveal != null || actions.open != null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: actions.reveal ?? actions.open,
            child: MouseRegion(cursor: SystemMouseCursors.click, child: title),
          )
        : title;
    final whereText = where.isEmpty || trial
        ? null
        : Text(
            where,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: uiText(TextSize.caption, color: ui.text3),
          );

    final links = [
      if (actions.terminal != null) _Link('Répondre dans le terminal', actions.terminal!),
      if (actions.later != null) _Link('Plus tard', actions.later!),
    ];
    final linkRow = links.isEmpty && actions.open == null
        ? null
        : Row(
            children: [
              for (final (i, l) in links.indexed) ...[if (i > 0) const SizedBox(width: 14), l],
              const Spacer(),
              if (actions.open != null) _Link('Voir l’agent', actions.open!),
            ],
          );

    final (:detail, :answers) = _parts(
      ui,
      links: [...links, if (actions.open != null) _Link('Voir l’agent', actions.open!)],
    );
    if (!trial) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          head,
          ?whereText,
          if (context_.isNotEmpty) ...[const SizedBox(height: 8), ...context_],
          const SizedBox(height: 10),
          ...detail,
          ?answers,
          if (linkRow != null) ...[const SizedBox(height: 8), linkRow],
        ],
      );
    }

    // The trial (2026-10-12): who asks stays at the top, the request and
    // its answers at the bottom, always in sight; the task between them
    // scrolls. A question: its card fills it, the links in its bar.
    final asking = answers is QuestionCard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        ?whereText,
        const SizedBox(height: 8),
        Expanded(
          child: asking
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Expanded(child: answers)],
                )
              : SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: context_),
                ),
        ),
        // The request itself stays with its answers.
        if (!asking && detail.isNotEmpty) ...[const SizedBox(height: 8), ...detail],
        if (!asking && answers != null) ...[if (detail.isEmpty) const SizedBox(height: 8), answers],
        if (linkRow != null && !asking) ...[const SizedBox(height: 6), linkRow],
      ],
    );
  }

  /// The request: what it is ([detail]), then how to answer it
  /// ([answers]).
  ///
  /// [links] go in the question card's bar, in the trial.
  ({List<Widget> detail, Widget? answers}) _parts(MikkyUi ui, {List<Widget> links = const []}) {
    final b = brief;
    final answer = actions.answer;
    switch (b.kind) {
      case BriefKind.approval:
        final diff = b.requestDiff;
        final change = b.requestChange;
        return (
          detail: [
            if (trial && (b.requestTitle != null || diff != null))
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (b.requestTitle != null)
                    Flexible(
                      child: Text(
                        b.requestTitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: uiText(TextSize.caption, color: ui.text2),
                      ),
                    ),
                  // A click opens the change (2026-10-08).
                  if (diff != null) ...[
                    const SizedBox(width: 8),
                    DiffCount(
                      added: diff.added,
                      removed: diff.removed,
                      path: change?.path,
                      changes: change == null ? null : [change],
                    ),
                  ],
                ],
              )
            else if (b.requestTitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  b.requestTitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(TextSize.caption, color: ui.text2),
                ),
              ),
          ],
          answers: _Keyed(
            keys: {
              RequestKey.yes: () => answer(AgentAnswer.allow),
              RequestKey.enter: () => answer(AgentAnswer.allow),
              RequestKey.no: () => answer(AgentAnswer.deny),
              if (canAlways) RequestKey.always: () => answer(AgentAnswer.allowAlways),
            },
            child: WaitActions(
              command: trial || diff == null ? b.request : '${b.request}  ${diff.label}',
              onYes: () => answer(AgentAnswer.allow),
              onNo: () => answer(AgentAnswer.deny),
              onAlways: canAlways ? () => answer(AgentAnswer.allowAlways) : null,
            ),
          ),
        );
      case BriefKind.question:
        final q = question;
        final onQuestion = actions.answerQuestion;
        if (q != null && onQuestion != null) {
          return (
            detail: const <Widget>[],
            answers: trial
                ? QuestionCard(question: q, onAnswer: onQuestion, trial: questionTrial, fill: true, barLeading: links)
                : QuestionCard(question: q, onAnswer: onQuestion),
          );
        }
        return (
          detail: [CodePill(b.request, maxLines: 4), const SizedBox(height: 8)],
          answers: Align(
            alignment: Alignment.centerRight,
            child: AnswerBar(answers: [('Plus tard', () => answer(AgentAnswer.dismiss))]),
          ),
        );
      case BriefKind.error:
        return (
          detail: [
            Text(
              b.request,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: uiText(TextSize.small, color: ui.red),
            ),
            const SizedBox(height: 8),
          ],
          answers: _Keyed(
            keys: {RequestKey.enter: () => answer(AgentAnswer.retry), RequestKey.no: () => answer(AgentAnswer.dismiss)},
            child: Align(
              alignment: Alignment.centerRight,
              child: AnswerBar(
                answers: [
                  ('Ignorer', () => answer(AgentAnswer.dismiss)),
                  ('Relancer', () => answer(AgentAnswer.retry)),
                ],
              ),
            ),
          ),
        );
      case BriefKind.finished:
        return (
          detail: [
            Text(
              b.request,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: uiText(TextSize.small, color: ui.text),
            ),
            if (b.files.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final f in b.files.take(4))
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: uiText(TextSize.caption, color: ui.text2, mono: true),
                      ),
                    ),
                    DiffCount(added: f.diff.added, removed: f.diff.removed, path: f.path, changes: f.changes),
                  ],
                ),
              if (b.files.length > 4)
                Text('+ ${b.files.length - 4} fichiers', style: uiText(TextSize.caption, color: ui.text3)),
            ],
            const SizedBox(height: 8),
          ],
          answers: _Keyed(
            keys: {RequestKey.enter: () => answer(AgentAnswer.dismiss)},
            child: Align(
              alignment: Alignment.centerRight,
              child: AnswerBar(answers: [('OK', () => answer(AgentAnswer.dismiss))]),
            ),
          ),
        );
      case BriefKind.rateLimited:
        final finish = actions.finishLimit, enchant = actions.enchant;
        final act = finish != null || enchant != null;
        return (
          detail: [
            if (b.request.isNotEmpty)
              Text(
                b.request,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: uiText(TextSize.small, color: ui.text),
              ),
            if (act) const SizedBox(height: 8),
          ],
          answers: act
              ? _Keyed(
                  keys: {RequestKey.enter: ?enchant, RequestKey.no: ?finish},
                  child: LimitActions(onFinish: finish, onSpell: enchant),
                )
              : null,
        );
      case BriefKind.working || BriefKind.idle:
        return (
          detail: [
            if (b.request.isNotEmpty)
              Text(
                b.request,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: uiText(TextSize.small, color: ui.text),
              ),
          ],
          answers: null,
        );
    }
  }

  static String _folder(String cwd) => cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ?? cwd;
}

/// Some of the island's keys for the request on screen (see
/// [RequestKeys]).
class _Keyed extends StatefulWidget {
  const _Keyed({required this.keys, required this.child});

  final Map<RequestKey, VoidCallback> keys;
  final Widget child;

  @override
  State<_Keyed> createState() => _KeyedState();
}

class _KeyedState extends State<_Keyed> with RequestKeysListener {
  @override
  bool onRequestKey(RequestKey key) {
    final action = widget.keys[key];
    action?.call();
    return action != null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

extension on AgentProvider {
  String get label => switch (this) {
    AgentProvider.claude => 'Claude',
    AgentProvider.codex => 'Codex',
  };
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.text, {required this.style});

  final String label, text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: style.copyWith(color: ui.text3),
            ),
            TextSpan(text: text),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// « Modifie main.dart +3 −1 », « cargo test » — what the agent did.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.a);

  final ActivityLine a;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final diff = a.diff;
    return Row(
      children: [
        Text(
          a.running ? '›' : (a.failed ? '×' : '·'),
          style: uiText(TextSize.caption, color: a.failed ? ui.red : ui.text3, mono: true),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            a.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: uiText(TextSize.caption, color: ui.text2, mono: true),
          ),
        ),
        if (diff != null)
          DiffCount(
            added: diff.added,
            removed: diff.removed,
            path: a.changes.firstOrNull?.path,
            changes: a.changes.isEmpty ? null : a.changes,
          ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          label,
          style: uiText(TextSize.caption, color: ui.text2, weight: FontWeight.w500),
        ),
      ),
    );
  }
}
