import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/content/cards.dart';
import '../ui/controls/sliding_hover.dart';
import '../ui/controls/step_tabs.dart';
import '../ui/foundation/icons.dart';
import '../ui/foundation/motion.dart';
import '../ui/foundation/tokens.dart';
import '../ui/pixels/pixel_fx.dart';
import 'request_keys.dart';

/// How a question card starts, on the boards; the app keeps the defaults.
class QuestionTrial {
  const QuestionTrial({this.other = false, this.answers = const {}, this.at});

  /// « Autre… » open.
  final bool other;

  /// Answers already given, by key.
  final Map<String, Object> answers;

  /// The question shown first; null: the first one left.
  final int? at;
}

/// A question with choices (Claude's question tool, through ACP or its
/// hooks — the same card for both, 2026-10-08): flat, like the answer
/// bar, never capsule buttons. An edge of pixels in our oranges along the
/// question and its choices says « ici, tu réponds » (2026-10-12, chosen:
/// « orange seul », glitched « en tranches », on three columns).
///
/// - One choice: a click on it answers, and goes to the next question
///   left.
/// - Several choices: tick them, then « Suivante » (« Envoyer » on the
///   last one left).
/// - « Autre… »: a line of its own (when the agent takes one); a second
///   click closes it and clears it.
/// - Several questions: one at a time, their titles above like tabs
///   ([StepTabs]); « Précédente » (or a click on an answered one) opens it
///   again, with
///   what was answered: another choice changes it, « Suivante » keeps it.
///   « Tout passer » skips the whole form.
/// - Keys (in a request): 1 to 4 pick a choice, Entrée goes on.
///
/// The answers go back by question key: the label chosen, the labels
/// ticked (a list), or the text written under the question's
/// [Question.otherKey]; null: skipped.
class QuestionCard extends StatefulWidget {
  const QuestionCard({
    super.key,
    required this.question,
    required this.onAnswer,
    this.trial = const QuestionTrial(),
    this.fill = false,
    this.barLeading = const [],
    this.elsewhere = const [],
    this.onElsewhere,
  });

  final QuestionAsked question;

  /// The answers by question key; null: skipped. Itself null: shown, not
  /// answered here (2026-10-13: asked in Claude's app or VS Code, which
  /// show it themselves) — the same card, its choices not clickable, and
  /// [elsewhere] in its bar.
  final ValueChanged<Map<String, Object>?>? onAnswer;

  /// How it starts (the boards).
  final QuestionTrial trial;

  /// Fills the height it is given: the question and its choices scroll,
  /// the answers stay at the bottom (in the notch's request, 2026-10-12).
  final bool fill;

  /// On the left of the answers (the request's links: « Plus tard »,
  /// « Voir l’agent »).
  final List<Widget> barLeading;

  /// The bar's answers when it is not answered here: « Répondre dans
  /// Claude ».
  final List<(String, VoidCallback)> elsewhere;

  /// A click on a choice when it is not answered here: where it is
  /// (« Répondre dans Claude »), instead of going through to the island.
  final VoidCallback? onElsewhere;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> with RequestKeysListener {
  /// What is answered so far, by key: the label chosen, the labels ticked,
  /// or the text written under the question's [Question.otherKey].
  late final Map<String, Object> _answers = {...widget.trial.answers};

  /// Which question shows (one at a time).
  late int _at = widget.trial.at ?? _firstLeft ?? 0;
  final Set<String> _ticked = {};

  /// The choice made before, on a question opened again.
  String? _chosen;
  bool _other = false;
  final _otherText = TextEditingController();
  final _otherFocus = FocusNode();

  List<Question> get _questions => widget.question.questions;
  Question get _question => _questions[_at];
  int get _count => _questions.length;

  @override
  void initState() {
    super.initState();
    _restore();
    if (widget.trial.other && _question.otherKey != null) _other = true;
  }

  @override
  void didUpdateWidget(QuestionCard old) {
    super.didUpdateWidget(old);
    // Another request, not the same one rebuilt: what was being answered
    // goes.
    if (old.question.requestId != widget.question.requestId) {
      _answers.clear();
      _at = 0;
      _restore();
    }
  }

  @override
  void dispose() {
    _otherText.dispose();
    _otherFocus.dispose();
    super.dispose();
  }

  bool _answered(int i) => _answers.containsKey(_questions[i].key) || _answers.containsKey(_questions[i].otherKey);

  int? get _firstLeft {
    for (var i = 0; i < _count; i++) {
      if (!_answered(i)) return i;
    }
    return null;
  }

  /// The question shown as it was answered (nothing, the first time).
  void _restore() {
    final q = _question;
    final given = _answers[q.key], written = _answers[q.otherKey];
    _ticked
      ..clear()
      ..addAll(given is List ? given.whereType<String>() : const <String>[]);
    _chosen = given is String ? given : null;
    _other = written is String;
    _otherText.text = written is String ? written : '';
  }

  void _go(int i) => setState(() {
    _at = i;
    _restore();
  });

  /// This question is answered with [value] (under [key]): the first one
  /// left, or all of them go.
  void _answer(String key, Object value) {
    final q = _question;
    _answers
      ..remove(q.key)
      ..remove(q.otherKey)
      ..[key] = value;
    final next = _firstLeft;
    if (next != null) {
      _go(next);
    } else {
      widget.onAnswer?.call(Map.of(_answers));
    }
  }

  void _pick(int i) {
    final q = _question;
    if (i >= q.choices.length) {
      if (i == q.choices.length && q.otherKey != null) _toggleOther();
      return;
    }
    final label = q.choices[i].label;
    if (q.multiple) {
      setState(() => _ticked.contains(label) ? _ticked.remove(label) : _ticked.add(label));
    } else {
      _answer(q.key, label);
    }
  }

  /// « Autre… » opens its line; a second click closes it and clears what
  /// was written (2026-10-12: it could not be unticked).
  void _toggleOther() {
    if (_other) {
      setState(() {
        _other = false;
        _otherText.clear();
      });
      return;
    }
    setState(() => _other = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _otherFocus.requestFocus();
    });
  }

  /// What is ticked or written, sent; null if nothing is.
  VoidCallback? get _send {
    final q = _question;
    final text = _otherText.text.trim();
    if (_other && text.isNotEmpty && q.otherKey != null) return () => _answer(q.otherKey!, text);
    if (q.multiple && _ticked.isNotEmpty) {
      return () => _answer(q.key, [
        for (final c in q.choices)
          if (_ticked.contains(c.label)) c.label,
      ]);
    }
    return null;
  }

  /// « Suivante » / « Envoyer »: what is ticked or written; on a question
  /// opened again, its answer kept, the next one.
  VoidCallback? get _goOn => _send ?? (_answered(_at) && _at + 1 < _count ? () => _go(_at + 1) : null);

  bool get _readOnly => widget.onAnswer == null;

  @override
  bool onRequestKey(RequestKey key) {
    if (_readOnly) return false;
    final i = key.choice;
    if (i != null) {
      final q = _question;
      if (i > q.choices.length || (i == q.choices.length && q.otherKey == null)) return false;
      _pick(i);
      return true;
    }
    if (key == RequestKey.enter) {
      final goOn = _goOn;
      goOn?.call();
      return goOn != null;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final q = _question;
    final title = _titleOf(q);
    final text = q.text.isNotEmpty ? q.text : widget.question.message;
    final rows = <Widget>[
      for (var i = 0; i < q.choices.length; i++)
        _ChoiceRow(
          index: i,
          label: q.choices[i].label,
          description: q.choices[i].description,
          multiple: q.multiple,
          ticked: _ticked.contains(q.choices[i].label) || q.choices[i].label == _chosen,
          onTap: _readOnly ? widget.onElsewhere : () => _pick(i),
        ),
      if (q.otherKey != null && !_readOnly)
        _ChoiceRow(
          index: q.choices.length,
          label: 'Autre…',
          description: _other ? null : 'Écrire ta réponse',
          multiple: false,
          ticked: _other,
          onTap: _toggleOther,
        ),
    ];
    final question = <Widget>[
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text),
            // In the notch, every line counts: on the question's line.
            if (q.multiple && widget.fill)
              TextSpan(
                text: '   Plusieurs choix possibles',
                style: uiText(TextSize.caption, color: ui.text3),
              ),
          ],
        ),
        style: uiText(TextSize.body, weight: FontWeight.w600, color: ui.text, height: 1.4),
      ),
      if (q.multiple && !widget.fill)
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text('Plusieurs choix possibles', style: uiText(TextSize.caption, color: ui.text3)),
        ),
      const SizedBox(height: 6),
      SlidingHover(
        child: widget.fill
            // The notch is wide and short: two columns of choices.
            ? LayoutBuilder(
                builder: (context, box) {
                  if (box.maxWidth < 440) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
                  final half = (box.maxWidth - 8) / 2;
                  return Wrap(
                    spacing: 8,
                    children: [for (final r in rows) SizedBox(width: half, child: r)],
                  );
                },
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ),
      if (_other)
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 4, 0, 0),
          child: _OtherField(
            controller: _otherText,
            focus: _otherFocus,
            onChanged: () => setState(() {}),
            onSubmitted: () => _send?.call(),
          ),
        ),
    ];
    final top = <Widget>[if (_count > 1 || title != null) _series(ui, title), _edged(ui, question)];
    // The last one left: what goes on sends the form.
    final last = !Iterable<int>.generate(_count).any((i) => i != _at && !_answered(i));
    final goOn = q.multiple || _other || _answered(_at);
    final answers = AnswerBar(
      key: ValueKey('bar-${_at > 0}-$goOn-$last'),
      answers: _readOnly
          ? widget.elsewhere
          : [
              if (_at > 0) ('Précédente', () => _go(_at - 1)),
              (_count > 1 ? 'Tout passer' : 'Passer', () => widget.onAnswer?.call(null)),
              if (goOn) (last ? 'Envoyer' : 'Suivante', _goOn),
            ],
    );
    final bar = widget.barLeading.isEmpty
        ? Align(alignment: Alignment.centerRight, child: answers)
        : Row(
            children: [
              for (final (i, w) in widget.barLeading.indexed) ...[if (i > 0) const SizedBox(width: 14), w],
              const Spacer(),
              answers,
            ],
          );
    return Column(
      key: ValueKey('question-$_at'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.fill)
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: top),
            ),
          )
        else
          ...top,
        const SizedBox(height: 8),
        bar,
      ],
    );
  }

  static String? _titleOf(Question q) => q.title != null && q.title!.isNotEmpty && q.title != q.text ? q.title : null;

  /// The text past the edge of pixels.
  static const _indent = 24.0;

  /// Above the question: with several, each one's title like a tab
  /// ([StepTabs]); with one, its title in grey.
  Widget _series(MikkyUi ui, String? title) => Padding(
    padding: const EdgeInsets.only(left: _indent, bottom: 3),
    child: _count > 1
        ? StepTabs(
            labels: [for (final (i, q) in _questions.indexed) _titleOf(q) ?? 'Question ${i + 1}'],
            at: _at,
            done: {
              for (var i = 0; i < _count; i++)
                if (_answered(i)) i,
            },
            onSelect: _go,
          )
        : Text(
            title!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: uiText(TextSize.caption, weight: FontWeight.w500, color: ui.text3),
          ),
  );

  /// The mark of a question: [PixelEdge.waiting] along it and its choices.
  Widget _edged(MikkyUi ui, List<Widget> children) => Stack(
    children: [
      Padding(
        padding: const EdgeInsets.only(left: _indent),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
      Positioned(left: 0, top: 4, bottom: 4, child: PixelEdge.waiting(ui)),
    ],
  );
}

/// One choice: its key (1 to 4) in a small square — a tick box when
/// several can be chosen — its label, its description in grey.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.index,
    required this.label,
    required this.multiple,
    required this.ticked,
    this.onTap,
    this.description,
  });

  final int index;
  final String label;
  final String? description;
  final bool multiple, ticked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final on = ticked;
    final mark = AnimatedContainer(
      duration: Motion.of(context, Motion.hover),
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: on ? ui.ink : ui.track, borderRadius: BorderRadius.circular(multiple ? 5 : 6)),
      child: on && multiple
          ? MikkyIcon('check', size: 13, color: ui.onInk, stroke: 2.4)
          : Text(
              index < 9 ? '${index + 1}' : '',
              style: uiText(
                TextSize.badge,
                weight: FontWeight.w600,
                mono: true,
                color: on ? ui.onInk : ui.text3,
                height: 1,
              ),
            ),
    );
    return HoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: mark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: uiText(TextSize.label, weight: FontWeight.w500, color: ui.text),
                ),
                if (description != null && description!.isNotEmpty)
                  Text(description!, style: uiText(TextSize.small, color: ui.text3, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The line of « Autre… »: our hollow field, one line; Entrée sends.
class _OtherField extends StatelessWidget {
  const _OtherField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onChanged, onSubmitted;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final style = uiText(TextSize.label, color: ui.text, height: 1.3);
    return GestureDetector(
      onTap: focus.requestFocus,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: ListenableBuilder(
          listenable: focus,
          builder: (context, _) => AnimatedContainer(
            duration: Motion.of(context, Motion.hover),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: focus.hasFocus ? ui.thumb : ui.track,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: focus.hasFocus ? ui.line : ui.track, width: .8),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => controller.text.isEmpty
                      ? IgnorePointer(
                          child: Text('Ta réponse…', maxLines: 1, style: style.copyWith(color: ui.text3)),
                        )
                      : const SizedBox.shrink(),
                ),
                EditableText(
                  controller: controller,
                  focusNode: focus,
                  style: style,
                  cursorColor: ui.text,
                  backgroundCursorColor: ui.text3,
                  selectionColor: ui.blue.withValues(alpha: .25),
                  cursorWidth: 1.5,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSubmitted(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
