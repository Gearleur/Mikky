import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../../side/session_cards.dart';
import '../../ui/cards.dart';
import '../../ui/tokens.dart';

/// What the user can do from a brief.
class BriefActions {
  const BriefActions({required this.answer, this.answerQuestion, this.open, this.terminal});

  /// Oui / Non / Toujours, Relancer, OK.
  final ValueChanged<AgentAnswer> answer;

  /// The answers to a question by key; null: skipped.
  final ValueChanged<Map<String, Object>?>? answerQuestion;

  /// The agent's page.
  final VoidCallback? open;

  /// Leave the request to the terminal it came from (sessions followed
  /// through Claude's hooks).
  final VoidCallback? terminal;
}

/// Everything about one request, as Mikky brings it (2026-10-04): who
/// asks and why, the task and its step, what the agent just said and did,
/// then the request and its answers.
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
  });

  final Agent agent;
  final TaskBrief brief;
  final BriefActions actions;

  /// A question with choices waiting for an answer.
  final QuestionAsked? question;

  /// The agent offers « Toujours ».
  final bool canAlways;

  /// Requests waiting, this one included (« 1/3 »).
  final int queue;

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

    final context_ = <Widget>[
      if (b.task != null) _Labeled('Tâche', b.task!, style: small),
      if (b.step != null) _Labeled('Étape', b.step!, style: small),
      if (b.said != null) _Labeled('Dit', '« ${b.said!} »', style: small),
      if (b.recent.isNotEmpty) ...[
        const SizedBox(height: 2),
        for (final a in b.recent) _ActivityRow(a),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: agent.name, style: uiText(TextSize.body, weight: FontWeight.w600, color: ui.text)),
                  TextSpan(text: '  $line', style: uiText(TextSize.small, color: ui.text2)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (queue > 1) ...[
              const SizedBox(width: 8),
              Text('1/$queue', style: uiText(TextSize.caption, color: ui.text3, tabular: true)),
            ],
          ],
        ),
        if (where.isNotEmpty) Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, color: ui.text3)),
        if (context_.isNotEmpty) ...[const SizedBox(height: 8), ...context_],
        const SizedBox(height: 10),
        ..._request(context, ui),
        if (actions.open != null || actions.terminal != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              if (actions.terminal != null) _Link('Répondre dans le terminal', actions.terminal!),
              const Spacer(),
              if (actions.open != null) _Link('Voir l’agent', actions.open!),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _request(BuildContext context, MikkyUi ui) {
    final b = brief;
    final answer = actions.answer;
    switch (b.kind) {
      case BriefKind.approval:
        final diff = b.requestDiff;
        return [
          if (b.requestTitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(b.requestTitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, color: ui.text2)),
            ),
          WaitActions(
            command: diff == null ? b.request : '${b.request}  ${diff.label}',
            onYes: () => answer(AgentAnswer.allow),
            onNo: () => answer(AgentAnswer.deny),
            onAlways: canAlways ? () => answer(AgentAnswer.allowAlways) : null,
          ),
        ];
      case BriefKind.question:
        final q = question;
        final onQuestion = actions.answerQuestion;
        if (q != null && onQuestion != null) return [QuestionCard(question: q, onAnswer: onQuestion)];
        return [
          CodePill(b.request, maxLines: 4),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: AnswerBar(answers: [('Plus tard', () => answer(AgentAnswer.dismiss))])),
        ];
      case BriefKind.error:
        return [
          Text(b.request, maxLines: 4, overflow: TextOverflow.ellipsis, style: uiText(TextSize.small, color: ui.red)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: AnswerBar(answers: [('Ignorer', () => answer(AgentAnswer.dismiss)), ('Relancer', () => answer(AgentAnswer.retry))]),
          ),
        ];
      case BriefKind.finished:
        return [
          Text(b.request, maxLines: 4, overflow: TextOverflow.ellipsis, style: uiText(TextSize.small, color: ui.text)),
          if (b.files.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final f in b.files.take(4))
              Row(
                children: [
                  Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, color: ui.text2, mono: true))),
                  _DiffLabel(f.diff),
                ],
              ),
            if (b.files.length > 4) Text('+ ${b.files.length - 4} fichiers', style: uiText(TextSize.caption, color: ui.text3)),
          ],
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: AnswerBar(answers: [('OK', () => answer(AgentAnswer.dismiss))])),
        ];
      case BriefKind.rateLimited || BriefKind.working || BriefKind.idle:
        return [
          if (b.request.isNotEmpty) Text(b.request, maxLines: 3, overflow: TextOverflow.ellipsis, style: uiText(TextSize.small, color: ui.text)),
        ];
    }
  }

  static String _folder(String cwd) => cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ?? cwd;
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
        TextSpan(children: [
          TextSpan(text: '$label  ', style: style.copyWith(color: ui.text3)),
          TextSpan(text: text),
        ]),
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
        Text(a.running ? '›' : (a.failed ? '×' : '·'), style: uiText(TextSize.caption, color: a.failed ? ui.red : ui.text3, mono: true)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(a.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, color: ui.text2, mono: true)),
        ),
        if (diff != null) _DiffLabel(diff),
      ],
    );
  }
}

class _DiffLabel extends StatelessWidget {
  const _DiffLabel(this.diff);

  final DiffStat diff;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final style = uiText(TextSize.caption, mono: true, tabular: true);
    return Text.rich(TextSpan(children: [
      TextSpan(text: '+${diff.added}', style: style.copyWith(color: ui.green)),
      const TextSpan(text: ' '),
      TextSpan(text: '−${diff.removed}', style: style.copyWith(color: ui.red)),
    ]));
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
        child: Text(label, style: uiText(TextSize.caption, color: ui.text2, weight: FontWeight.w500)),
      ),
    );
  }
}
