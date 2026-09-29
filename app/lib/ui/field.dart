import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'buttons.dart';
import 'icons.dart';
import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

/// The text itself, for both fields: widgets-level, Geist, the ink caret.
class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.placeholder,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final String placeholder;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Stack(children: [
      ListenableBuilder(
        listenable: controller,
        builder: (context, _) => controller.text.isEmpty
            ? IgnorePointer(child: Text(placeholder, maxLines: 1, overflow: TextOverflow.clip, style: style.copyWith(color: ui.text3)))
            : const SizedBox.shrink(),
      ),
      EditableText(
        controller: controller,
        focusNode: focusNode,
        style: style.copyWith(color: ui.text),
        cursorColor: ui.text,
        backgroundCursorColor: ui.text3,
        selectionColor: ui.blue.withValues(alpha: .25),
        cursorWidth: 1.5,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: maxLines > 1 ? TextInputType.multiline : TextInputType.text,
        textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
      ),
    ]);
  }
}

/// `.field`: a hollow capsule, 44 px, up to 380 px wide; white with an
/// ink ring while focused.
class SearchField extends StatefulWidget {
  const SearchField({super.key, this.controller, this.placeholder = '', this.icon, this.onSubmitted});

  final TextEditingController? controller;
  final String placeholder;
  final String? icon;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final focused = _focus.hasFocus;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: GestureDetector(
        onTap: _focus.requestFocus,
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: Surface(
            height: 44,
            color: focused ? ui.thumb : ui.track,
            shadows: focused ? ui.focusRing : ui.inset,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              if (widget.icon != null) ...[MikkyIcon(widget.icon!, size: 18, color: ui.text2), const SizedBox(width: 8)],
              Expanded(
                child: _Input(controller: _controller, focusNode: _focus, style: uiText(14.5, height: 1.2), placeholder: widget.placeholder),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The field of the window (`.cbox`, « Champ »): grey and hollow, the text
/// grows from one line to five, then scrolls. On the right, a small mic
/// and the send arrow. [options] sit half inside, bottom left: folder and
/// model (new agent) or Suivi | Chat (agent at work). Enter sends,
/// Shift + Enter goes to the next line.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder = 'Écris ou parle…',
    this.options,
    this.onSend,
    this.onMic,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String placeholder;
  final Widget? options;
  final ValueChanged<String>? onSend;
  final VoidCallback? onMic;
  final bool autofocus;

  /// How far the options hang below the field.
  static const optionsOverhang = 12.0;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    _focus.onKeyEvent = _onKey;
    if (widget.autofocus) WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _changed() => setState(() {});

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend?.call(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final focused = _focus.hasFocus;
    final field = GestureDetector(
      onTap: _focus.requestFocus,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Surface(
            radius: 26,
            color: focused ? ui.thumb : ui.track,
            shadows: focused ? ui.focusRing : ui.inset,
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _Input(
                      controller: _controller,
                      focusNode: _focus,
                      style: uiText(14, height: 20 / 14),
                      placeholder: widget.placeholder,
                      maxLines: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                RoundButton('mic', size: 32, ghost: true, onPressed: widget.onMic, tooltip: 'Parler (Ctrl + Win maintenus)'),
                const SizedBox(width: 6),
                RoundButton('up', size: 32, ink: true, onPressed: _send, tooltip: 'Envoyer'),
              ]),
            ),
          ),
      ),
    );
    final options = widget.options;
    if (options == null) return field;
    return Padding(
      padding: const EdgeInsets.only(bottom: Composer.optionsOverhang),
      child: Stack(clipBehavior: Clip.none, children: [
        field,
        Positioned(left: 14, bottom: -Composer.optionsOverhang, child: options),
      ]),
    );
  }
}

/// `.cchip`: an option half inside the field (folder, model).
class ComposerChip extends StatelessWidget {
  const ComposerChip(this.label, {super.key, this.icon, this.onTap});

  final String label;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Pressable(
      onTap: onTap,
      pressedScale: .95,
      child: Surface(
        height: 24,
        color: ui.thumb,
        shadows: [...ui.shThumb, CssShadow(0, 0, 0, ui.island, spread: 3)],
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[MikkyIcon(icon!, size: 13, color: ui.text), const SizedBox(width: 4)],
          Text(label, style: uiText(11.5, weight: FontWeight.w600, color: ui.text, height: 1)),
          const SizedBox(width: 4),
          MikkyIcon('down', size: 11, color: ui.text2),
        ]),
      ),
    );
  }
}
