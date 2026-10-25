import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/content/cards.dart';
import '../ui/content/request_content.dart';
import '../ui/controls/sliding_hover.dart';
import '../ui/controls/step_tabs.dart';
import '../ui/foundation/icons.dart';
import '../ui/foundation/motion.dart';
import '../ui/foundation/tokens.dart';
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

typedef _QuestionEdit = ({Set<String> ticked, String? chosen, bool other, String text});

/// Kept by the request's owner while its card is deferred or replaced.
/// Contains no transport state and is discarded when the request settles.
class QuestionDraft {
  Object? _request;
  int? _at;
  final _answers = <String, Object>{};
  final _edits = <String, _QuestionEdit>{};
}

/// A question with choices (Claude's question tool, through ACP or its
/// hooks — the same card for both, 2026-10-08): flat, like the answer
/// bar, never capsule buttons. An edge of pixels in our oranges along the
/// question and its choices says « ici, tu réponds » (2026-10-12, chosen:
/// « orange seul », glitched « en tranches », on three columns).
///
/// - One choice: a click keeps it and goes to the next question. A series
///   is sent only with its final Envoyer button; a standalone choice sends.
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
    this.onLater,
    this.actionsAlignment = Alignment.centerRight,
    this.draft,
    this.before = const [],
    this.scroll,
    this.contentAnchor,
  });

  final QuestionAsked question;
  final QuestionDraft? draft;
  final List<Widget> before;
  final ScrollController? scroll;
  final GlobalKey? contentAnchor;

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

  /// Defer without submitting or skipping the form (the home notch).
  final VoidCallback? onLater;

  final Alignment actionsAlignment;

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> with RequestKeysListener {
  /// What is answered so far, by key: the label chosen, the labels ticked,
  /// or the text written under the question's [Question.otherKey].
  late QuestionDraft _draft;
  Map<String, Object> get _answers => _draft._answers;

  /// Which question shows (one at a time).
  int get _at => _draft._at!;
  set _at(int value) => _draft._at = value;
  final Set<String> _ticked = {};
  Map<String, _QuestionEdit> get _drafts => _draft._edits;

  /// The choice made before, on a question opened again.
  String? _chosen;
  bool _other = false;
  bool _submitted = false;
  final _otherText = TextEditingController();
  final _otherFocus = FocusNode();

  List<Question> get _questions => widget.question.questions;
  Question get _question => _questions[_at];
  int get _count => _questions.length;

  @override
  void initState() {
    super.initState();
    _loadDraft();
    _restore();
    if (widget.trial.other && _question.otherKey != null) _other = true;
  }

  void _loadDraft() {
    _draft = widget.draft ?? QuestionDraft();
    if (_draft._request != widget.question.requestId) {
      _draft._request = widget.question.requestId;
      _answers
        ..clear()
        ..addAll(widget.trial.answers);
      _drafts.clear();
      _draft._at = null;
    }
    _draft._at ??= widget.trial.at ?? _firstLeft ?? 0;
  }

  void _saveDraft() {
    _drafts[_question.key] = (ticked: Set.of(_ticked), chosen: _chosen, other: _other, text: _otherText.text);
  }

  @override
  void didUpdateWidget(QuestionCard old) {
    super.didUpdateWidget(old);
    // Another request, not the same one rebuilt: what was being answered
    // goes.
    if (old.question.requestId != widget.question.requestId || old.draft != widget.draft) {
      if (old.question.requestId == widget.question.requestId) _saveDraft();
      _loadDraft();
      _restore();
      _submitted = false;
    }
  }

  @override
  void dispose() {
    _saveDraft();
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
    final draft = _drafts[q.key];
    if (draft != null) {
      _ticked
        ..clear()
        ..addAll(draft.ticked);
      _chosen = draft.chosen;
      _other = draft.other;
      _otherText.text = draft.text;
      return;
    }
    final given = _answers[q.key], written = _answers[q.otherKey];
    _ticked
      ..clear()
      ..addAll(given is List ? given.whereType<String>() : const <String>[]);
    _chosen = given is String ? given : null;
    _other = written is String;
    _otherText.text = written is String ? written : '';
  }

  void _go(int i, {bool save = true}) {
    setState(() {
      if (save) _saveDraft();
      _at = i;
      _restore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.contentAnchor != null && widget.scroll != null) {
        revealRequest(widget.contentAnchor!, widget.scroll!);
      }
    });
  }

  /// Keep the answer and advance in reading order. Only an explicit final
  /// action (or a standalone choice) sends the form.
  void _answer(String key, Object value, {bool submit = false}) {
    if (_submitted) return;
    final q = _question;
    _drafts.remove(q.key);
    _answers
      ..remove(q.key)
      ..remove(q.otherKey)
      ..[key] = value;
    if (_count == 1 || submit) {
      _submit();
    } else {
      _go((_at + 1).clamp(0, _count - 1), save: false);
    }
  }

  void _submit() {
    if (_submitted) return;
    // Tabs can leave a changed answer without pressing Suivante. The final
    // confirmation must use those edits, never an older validated value.
    for (final q in _questions) {
      final edit = _drafts[q.key];
      if (edit == null) continue;
      _answers
        ..remove(q.key)
        ..remove(q.otherKey);
      if (edit.other) {
        if (q.otherKey != null && edit.text.trim().isNotEmpty) _answers[q.otherKey!] = edit.text.trim();
      } else if (q.multiple) {
        final values = [
          for (final c in q.choices)
            if (edit.ticked.contains(c.label)) c.label,
        ];
        if (values.isNotEmpty) _answers[q.key] = values;
      } else if (edit.chosen != null) {
        _answers[q.key] = edit.chosen!;
      }
    }
    if (_firstLeft case final left?) {
      _go(left, save: false);
      return;
    }
    _submitted = true;
    widget.onAnswer?.call(Map.of(_answers));
  }

  void _pick(int i) {
    if (_submitted) return;
    final q = _question;
    if (i >= q.choices.length) {
      if (i == q.choices.length && q.otherKey != null) _toggleOther();
      return;
    }
    final label = q.choices[i].label;
    if (q.multiple) {
      setState(() {
        _other = false;
        _otherText.clear();
        _ticked.contains(label) ? _ticked.remove(label) : _ticked.add(label);
      });
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
    setState(() {
      _other = true;
      _ticked.clear();
      _chosen = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _otherFocus.requestFocus();
    });
  }

  /// What is ticked or written, sent; null if nothing is.
  VoidCallback? get _send {
    final q = _question;
    final text = _otherText.text.trim();
    if (_other && text.isNotEmpty && q.otherKey != null) {
      return () => _answer(q.otherKey!, text, submit: _at == _count - 1);
    }
    if (q.multiple && _ticked.isNotEmpty) {
      return () => _answer(q.key, [
        for (final c in q.choices)
          if (_ticked.contains(c.label)) c.label,
      ], submit: _at == _count - 1);
    }
    return null;
  }

  /// « Suivante » / « Envoyer »: what is ticked or written; on a question
  /// opened again, its answer kept, the next one.
  VoidCallback? get _goOn =>
      _send ??
      (!_question.multiple && !_other && _answered(_at) ? (_at + 1 < _count ? () => _go(_at + 1) : _submit) : null);

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
          compact: widget.fill,
          ticked: _ticked.contains(q.choices[i].label) || q.choices[i].label == _chosen,
          onTap: _readOnly ? widget.onElsewhere : () => _pick(i),
        ),
      if (q.otherKey != null && !_readOnly)
        _ChoiceRow(
          index: q.choices.length,
          label: 'Autre…',
          description: _other ? null : 'Écrire une réponse à la place des choix',
          multiple: false,
          compact: widget.fill,
          ticked: _other,
          onTap: _toggleOther,
        ),
    ];
    final question = <Widget>[
      Text(
        text,
        style: uiText(TextSize.body, weight: FontWeight.w600, color: ui.text, height: 1.4),
      ),
      if (q.multiple)
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            _other
                ? 'Réponse libre · remplace les choix'
                : _ticked.isEmpty
                ? 'Plusieurs choix possibles · sélectionne puis valide'
                : '${_ticked.length} ${_ticked.length == 1 ? 'réponse sélectionnée' : 'réponses sélectionnées'}',
            style: uiText(TextSize.caption, color: _ticked.isEmpty ? ui.text3 : ui.blue),
          ),
        ),
      const SizedBox(height: 6),
      SlidingHover(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
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
    // Reading order is stable even when previous answers are edited.
    final last = _at == _count - 1;
    final goOn = q.multiple || _other || _answered(_at);
    final answers = AnswerBar(
      key: ValueKey('bar-${_at > 0}-$goOn-$last'),
      answers: _readOnly
          ? widget.elsewhere
          : [
              if (_at > 0) ('Précédente', () => _go(_at - 1)),
              if (widget.onLater != null)
                ('Plus tard', widget.onLater)
              else
                (_count > 1 ? 'Tout passer' : 'Passer', () => widget.onAnswer?.call(null)),
              if (goOn) (last ? 'Envoyer' : 'Suivante', _goOn),
            ],
    );
    final bar = widget.barLeading.isEmpty
        ? Align(alignment: widget.actionsAlignment, child: answers)
        : Row(
            children: [
              for (final (i, w) in widget.barLeading.indexed) ...[if (i > 0) const SizedBox(width: 14), w],
              const Spacer(),
              answers,
            ],
          );
    return RequestContent(
      fill: widget.fill,
      before: widget.before,
      scroll: widget.scroll,
      contentAnchor: widget.contentAnchor,
      heading: _count > 1 || title != null ? _series(ui, title) : null,
      actions: bar,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: question),
    );
  }

  static String? _titleOf(Question q) => q.title != null && q.title!.isNotEmpty && q.title != q.text ? q.title : null;

  /// Above the question: with several, each one's title like a tab
  /// ([StepTabs]); with one, its title in grey.
  Widget _series(MikkyUi ui, String? title) => _count > 1
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
    this.compact = false,
    this.onTap,
    this.description,
  });

  final int index;
  final String label;
  final String? description;
  final bool multiple, ticked, compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final on = ticked;
    final words = [
      Text(
        label,
        style: uiText(TextSize.label, weight: FontWeight.w500, color: ui.text),
      ),
      if (description != null && description!.isNotEmpty)
        Text(description!, style: uiText(TextSize.small, color: ui.text3, height: 1.35)),
    ];
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
    return Semantics(
      checked: multiple ? ticked : null,
      selected: multiple ? null : ticked,
      button: true,
      child: HoverRow(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: mark),
            const SizedBox(width: 10),
            Expanded(
              child: compact
                  ? Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: words)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: words),
            ),
          ],
        ),
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
