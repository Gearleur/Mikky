import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/enchant.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/cards.dart';
import '../ui/pixel_fx.dart';
import '../ui/selectors.dart';
import '../ui/status.dart';
import '../ui/surface.dart';
import '../ui/tokens.dart';
import 'session_steps.dart';
import 'session_text.dart';

// The cards of an agent's thread and of the home: its limit and its spell,
// a permission to give, a question to answer, a pause.

/// What an agent's page lends the thread to act on a limit: which agent,
/// and how to write to it.
class LimitHooks {
  const LimitHooks(this.id, this.send, {this.finish});

  final String id;
  final Future<void> Function(String text) send;

  /// « Terminer »: no more waiting for the limit; the session counts as done.
  final VoidCallback? finish;
}

/// What can be done about a limit (user request, 2026-10-01): two separate
/// buttons, « Terminer » (no more waiting, the session counts as done) and
/// « Relance auto » (Mikky relaunches it when the limit lifts). Under the
/// spell, only « Terminer », to refuse the relaunch.
class LimitActions extends StatelessWidget {
  const LimitActions({super.key, this.onFinish, this.onSpell});

  final VoidCallback? onFinish, onSpell;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (onFinish != null) MButton('Terminer', small: true, onPressed: onFinish),
      if (onFinish != null && onSpell != null) const SizedBox(width: 8),
      if (onSpell != null) MButton('Relance auto', small: true, onPressed: onSpell),
    ]),
  );
}


/// The limit card, tied to the spell of its agent (relaunched by itself
/// when the limit lifts, set in its ··· menu).
class LimitBlock extends StatefulWidget {
  const LimitBlock({super.key, required this.log, this.message, this.hooks});

  final SessionLog log;
  final String? message;
  final LimitHooks? hooks;

  @override
  State<LimitBlock> createState() => _LimitBlockState();
}

class _LimitBlockState extends State<LimitBlock> {
  final _spells = Enchantments.instance;

  @override
  void initState() {
    super.initState();
    _spells.addListener(_changed);
  }

  @override
  void dispose() {
    _spells.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final h = widget.hooks;
    final resets = widget.log.limitResetsAt;
    return LimitCard(
      resetsAt: resets,
      message: widget.message,
      relaunchAt: h == null ? null : _spells.relaunchAt(h.id),
      relaunched: h != null && _spells.isOn(h.id) && _spells.relaunchAt(h.id) == null,
      onFinish: h?.finish,
      onSpell: h == null ? null : () => _spells.enchant(h.id, resets, h.send),
    );
  }
}

/// An agent stopped by its limit, on the home: its logo, the yellow star,
/// when it lifts, « Terminer » and « Relance auto »; under the spell a plain
/// row, « Ensorcelé · se relance à 17 h 11 », nothing to press — the
/// spell comes off in its ··· menu (user requests, 2026-09-30).
class LimitedAgentCard extends StatelessWidget {
  const LimitedAgentCard({
    super.key,
    required this.id,
    required this.title,
    required this.log,
    required this.send,
    this.who = '',
    this.brand,
    this.pinned = false,
    this.onTap,
    this.onMenu,
    this.onFinish,
  });

  final String id;
  final String title;
  final SessionLog log;
  final Future<void> Function(String text) send;
  final String who;
  final Brand? brand;
  final bool pinned;
  final VoidCallback? onTap, onMenu;

  /// « Terminer »: no more waiting for the limit; the session counts as done.
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Enchantments.instance,
    builder: (context, _) {
      final spells = Enchantments.instance;
      final at = spells.relaunchAt(id);
      final spell = spells.isOn(id);
      final resets = log.limitResetsAt;
      // Under the spell the row looks like any other (its line says when
      // it relaunches); only a limit left alone keeps the yellow star (user
      // request, 2026-09-30).
      final Widget? mark = spell ? null : const PixelStar(PixelFxPalette.yellow, size: 11);
      return AgentCard(
        status: UiStatus.limited,
        title: title,
        who: who,
        brand: brand,
        pinned: pinned,
        style: AgentCardStyle.waiting,
        // The spell's violet star, alive; the limit's yellow one, still.
        mark: mark,
        subtitle: spell
            ? (at == null ? 'Ensorcelé · relancé' : 'Ensorcelé · se relance à ${hourText(at)}')
            : limitLine(resets),
        onTap: onTap,
        onMenu: onMenu,
        actions: LimitActions(onFinish: onFinish, onSpell: spell ? null : () => spells.enchant(id, resets, send)),
      );
    },
  );
}

/// Top middle of an agent's page: the violet star while it is under the
/// spell, the yellow one while its limit holds it (user requests,
/// 2026-09-30).
class SpellStar extends StatelessWidget {
  const SpellStar({super.key, required this.id, this.limited = false, this.force = false});

  final String id;

  /// Stopped by its subscription's limit.
  final bool limited;

  /// Shown as under the spell whatever the spells say (boards).
  final bool force;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Enchantments.instance,
    builder: (context, _) => force || Enchantments.instance.isOn(id)
        ? const IgnorePointer(child: SpellFx(size: 20))
        : limited
        ? const IgnorePointer(child: StatusFx(UiStatus.limited, size: 20))
        : const SizedBox.shrink(),
  );
}

/// The violet star after « Agents » while the global « Relance
/// automatique » is on (it is set in the home's ··· menu).
class AutoRelaunchMark extends StatelessWidget {
  const AutoRelaunchMark({super.key, this.force = false});

  /// Shown whatever the setting says (boards).
  final bool force;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Enchantments.instance,
    builder: (context, _) => force || Enchantments.instance.everywhere
        ? const Padding(padding: EdgeInsets.only(left: 8, top: 2), child: SpellFx(size: 14))
        : const SizedBox.shrink(),
  );
}

/// A subscription's limit reached: the yellow state and when it lifts
/// (user request, 2026-09-30), « Terminer » and « Relance auto ». Once
/// under the spell there is no card any more, only « Ensorcelé · se
/// relance à 17 h 11 », big, with the violet star, and « Terminer ».
class LimitCard extends StatelessWidget {
  const LimitCard({super.key, this.resetsAt, this.message, this.relaunchAt, this.relaunched = false, this.onFinish, this.onSpell});

  final DateTime? resetsAt;
  final String? message;

  /// Under the spell: when Mikky relaunches it.
  final DateTime? relaunchAt;

  /// Under the spell, the relaunch sent.
  final bool relaunched;

  /// See [LimitActions].
  final VoidCallback? onFinish, onSpell;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    if (relaunchAt != null || relaunched) {
      final spell = Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
        child: Row(children: [
          const SpellFx(size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Ensorcelé', style: uiText(TextSize.heading, weight: FontWeight.w600, color: ui.text, height: 1.3)),
                TextSpan(
                  text: relaunched ? ' · relancé' : ' · se relance à ${hourText(relaunchAt!)}',
                  style: uiText(TextSize.lead, color: ui.text2, height: 1.3),
                ),
              ]),
            ),
          ),
        ]),
      );
      if (onFinish == null || relaunched) return spell;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [spell, const SizedBox(height: 6), LimitActions(onFinish: onFinish)]);
    }
    return AgentCard(
      status: UiStatus.limited,
      title: 'Limite de l’abonnement atteinte',
      who: '',
      subtitle: resetsAt == null ? (message ?? 'Réessaie plus tard') : 'Reprend à ${hourText(resetsAt!)}',
      actions: onFinish == null && onSpell == null ? null : LimitActions(onFinish: onFinish, onSpell: onSpell),
    );
  }
}

/// The permission request at the bottom of the thread: what it asks, the
/// command, Oui / Non.
class AskCard extends StatelessWidget {
  const AskCard({super.key, required this.log, required this.onAnswer});

  final SessionLog log;
  final ValueChanged<AgentAnswer> onAnswer;

  @override
  Widget build(BuildContext context) => AgentCard(
        status: UiStatus.approval,
        title: askLabel(log),
        who: '',
        style: AgentCardStyle.waiting,
        actions: WaitActions(
          command: log.detail,
          onYes: () => onAnswer(AgentAnswer.allow),
          onNo: () => onAnswer(AgentAnswer.deny),
          onAlways: canAlways(log) ? () => onAnswer(AgentAnswer.allowAlways) : null,
        ),
      );
}

/// An agent put on hold: its turn stopped, its session kept. « Reprendre »
/// tells it to go on where it stopped (a message does too).
class PausedCard extends StatelessWidget {
  const PausedCard({super.key, required this.onResume});

  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) => AgentCard(
        status: UiStatus.paused,
        title: 'En pause',
        who: '',
        subtitle: 'Travail arrêté, session gardée',
        actions: Align(alignment: Alignment.centerRight, child: AnswerBar(answers: [('Reprendre', onResume)])),
      );
}


/// A question with choices (Claude's question tool): the question, its
/// choices as chips (one, or several), then Envoyer — or Passer, to let
/// the agent go on without an answer.
class QuestionCard extends StatefulWidget {
  const QuestionCard({super.key, required this.question, required this.onAnswer});

  final QuestionAsked question;

  /// The answers by question key; null: skipped.
  final ValueChanged<Map<String, Object>?> onAnswer;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  final Map<String, Set<String>> _picked = {};

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final q = widget.question;
    final complete = q.questions.every((x) => (_picked[x.key] ?? const {}).isNotEmpty);
    return Surface(
      radius: Radii.xl,
      color: ui.well,
      shadows: [ui.waitRing],
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (q.questions.length > 1 || q.questions.first.text.isEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(q.message, style: uiText(TextSize.body, weight: FontWeight.w600, color: ui.text))),
        for (final x in q.questions) ...[
          if (x.text.isNotEmpty) Text(x.text, style: uiText(q.questions.length > 1 ? TextSize.label : TextSize.body, weight: FontWeight.w600, color: ui.text)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in x.choices)
              MChip(
                c.label,
                on: _picked[x.key]?.contains(c.label) ?? false,
                onTap: () => setState(() {
                  final set = _picked[x.key] ??= {};
                  if (x.multiple) {
                    set.contains(c.label) ? set.remove(c.label) : set.add(c.label);
                  } else {
                    set
                      ..clear()
                      ..add(c.label);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 10),
        ],
        Row(children: [
          MButton('Passer', small: true, kind: ButtonKind.ghost, onPressed: () => widget.onAnswer(null)),
          const Spacer(),
          MButton(
            'Envoyer',
            small: true,
            kind: ButtonKind.primary,
            onPressed: complete
                ? () => widget.onAnswer({
                      for (final x in q.questions)
                        x.key: x.multiple ? _picked[x.key]!.toList() : _picked[x.key]!.first,
                    })
                : null,
          ),
        ]),
      ]),
    );
  }
}

/// What is left of the subscriptions, at the top of the home (user
/// request, 2026-10-01; Codex tells it, Claude does not): a small logo and
/// « 69 % des 5 h, repart à 17 h 10 · 70 % de la semaine », in grey.
class SubscriptionLimits extends StatelessWidget {
  const SubscriptionLimits(this.lines, {super.key});

  final List<(Brand, String)> lines;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (brand, text) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 1), child: BrandLogo(brand, size: 12)),
                const SizedBox(width: 6),
                Expanded(child: Text(text, style: uiText(11.5, color: ui.text3, height: 1.3, tabular: true))),
              ]),
            ),
        ],
      ),
    );
  }
}
