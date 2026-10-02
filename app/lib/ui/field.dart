import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'buttons.dart';
import 'icons.dart';
import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

/// The text itself, for both fields: widgets-level, Geist, the ink caret.
class _Input extends StatelessWidget {
  const _Input({required this.controller, required this.focusNode, required this.style, required this.placeholder, this.maxLines = 1});

  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final String placeholder;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Stack(
      children: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.text.isEmpty
              ? IgnorePointer(
                  child: Text(
                    placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: style.copyWith(color: ui.text3),
                  ),
                )
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
      ],
    );
  }
}

/// `.field`: a hollow capsule, 44 px, up to 380 px wide; white with an
/// ink ring while focused.
class SearchField extends StatefulWidget {
  const SearchField({super.key, this.controller, this.placeholder = '', this.icon, this.onSubmitted, this.small = false});

  /// 36 px instead of 44 (in a sheet, 2026-10-02).
  final bool small;

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
            height: widget.small ? 36 : 44,
            color: focused ? ui.thumb : ui.track,
            shadows: focused ? ui.focusRing : ui.inset,
            padding: EdgeInsets.symmetric(horizontal: widget.small ? 13 : 16),
            child: Row(
              children: [
                if (widget.icon != null) ...[MikkyIcon(widget.icon!, size: widget.small ? 16 : 18, color: ui.text2), SizedBox(width: widget.small ? 7 : 8)],
                Expanded(
                  child: _Input(controller: _controller, focusNode: _focus, style: uiText(widget.small ? TextSize.label : TextSize.body, height: 1.2), placeholder: widget.placeholder),
                ),
              ],
            ),
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
/// Shift + Enter goes to the next line. A « / » at the start shows the
/// agent's [commands] above the field: ↑ ↓ to choose, Tab or Enter to
/// take one.
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
    this.onEmptySend,
    this.commands = const [],
    this.glass = false,
  });

  /// Frosted: see-through and blurred, for a field the thread passes
  /// under (an agent's page).
  final bool glass;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String placeholder;
  final Widget? options;
  final ValueChanged<String>? onSend;
  final VoidCallback? onMic;

  /// Send with nothing written (null: nothing happens).
  final VoidCallback? onEmptySend;
  final bool autofocus;

  /// The agent's « / » commands.
  final List<AgentCommand> commands;

  /// How far the options hang below the field: half inside it.
  static const optionsOverhang = 12.0;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  /// The command picked in the list above the field.
  final _pick = ValueNotifier(0);
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    _controller.addListener(_textChanged);
    _focus.onKeyEvent = _onKey;
    if (widget.autofocus) WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _changed() => setState(() {});

  void _textChanged() {
    if (_controller.text == _lastText) return;
    _lastText = _controller.text;
    _pick.value = 0;
  }

  /// The commands that match what is typed (« /co » → compact…), while
  /// the text is a « / » and one word.
  List<AgentCommand> get _matches {
    final text = _controller.text;
    if (widget.commands.isEmpty || !text.startsWith('/') || text.contains(RegExp(r'\s'))) return const [];
    final q = text.substring(1).toLowerCase();
    final starts = [for (final c in widget.commands) if (c.name.toLowerCase().startsWith(q)) c];
    final inside = [for (final c in widget.commands) if (!c.name.toLowerCase().startsWith(q) && c.name.toLowerCase().contains(q)) c];
    final all = [...starts, ...inside];
    // Typed in full: Enter sends it.
    if (all.length == 1 && all.single.name.toLowerCase() == q) return const [];
    return all.take(6).toList();
  }

  void _take(AgentCommand c) {
    final text = '/${c.name} ';
    _controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    final matches = _matches;
    if (matches.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
        _pick.value = (_pick.value + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) % matches.length;
        return KeyEventResult.handled;
      }
      final enter = key == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed;
      if (e is KeyDownEvent && (key == LogicalKeyboardKey.tab || enter)) {
        _take(matches[_pick.value.clamp(0, matches.length - 1)]);
        return KeyEventResult.handled;
      }
    }
    if (e is! KeyDownEvent || key != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return widget.onEmptySend?.call();
    widget.onSend?.call(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _controller.removeListener(_textChanged);
    _pick.dispose();
    if (widget.focusNode == null) _focus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// Glass: the blurred thread behind the field's own see-through color.
  Widget _frost(Widget surface) => !widget.glass
      ? surface
      : Stack(children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xxl),
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: const SizedBox.expand()),
            ),
          ),
          surface,
        ]);

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final focused = _focus.hasFocus;
    final field = GestureDetector(
      onTap: _focus.requestFocus,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        // Slim, like the latest iPhone's (user request, 2026-09-30): 40
        // high, a full pill; 8 more at the bottom when options sit half
        // inside it, so they never cover the text.
        child: _frost(Surface(
          radius: Radii.xxl,
          color: widget.glass ? (focused ? ui.thumb : ui.track).withValues(alpha: focused ? .82 : .62) : (focused ? ui.thumb : ui.track),
          shadows: focused ? ui.focusRing : ui.inset,
          padding: EdgeInsets.fromLTRB(15, 4, 5, widget.options == null ? 4 : 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _Input(
                      controller: _controller,
                      focusNode: _focus,
                      style: uiText(TextSize.body, height: 20 / TextSize.body),
                      placeholder: widget.placeholder,
                      maxLines: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                RoundButton('mic', size: 30, ghost: true, onPressed: widget.onMic, tooltip: 'Parler (Ctrl + Win maintenus)'),
                const SizedBox(width: 2),
                RoundButton('up', size: 30, ink: true, onPressed: _send, tooltip: 'Envoyer'),
              ],
            ),
          ),
        )),
      ),
    );
    final options = widget.options;
    final withOptions = options == null
        ? field
        : Padding(
            padding: const EdgeInsets.only(bottom: Composer.optionsOverhang),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                field,
                Positioned(left: 14, bottom: -Composer.optionsOverhang, child: options),
              ],
            ),
          );
    if (widget.commands.isEmpty) return withOptions;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListenableBuilder(
        listenable: Listenable.merge([_controller, _pick]),
        builder: (context, _) {
          final matches = _matches;
          if (matches.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CommandList(commands: matches, picked: _pick.value.clamp(0, matches.length - 1), onTake: _take),
          );
        },
      ),
      withOptions,
    ]);
  }
}

/// The agent's commands that match, above the field.
class _CommandList extends StatelessWidget {
  const _CommandList({required this.commands, required this.picked, required this.onTake});

  final List<AgentCommand> commands;
  final int picked;
  final ValueChanged<AgentCommand> onTake;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Surface(
      radius: Radii.xl,
      color: ui.thumb,
      shadows: ui.shThumb,
      padding: const EdgeInsets.all(5),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < commands.length; i++)
          GestureDetector(
            onTap: () => onTake(commands[i]),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: i == picked ? ui.hover : null, borderRadius: BorderRadius.circular(Radii.lg)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('/${commands[i].name}', style: uiText(TextSize.small, mono: true, weight: FontWeight.w500, color: ui.text, height: 1.3)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      commands[i].hint ?? commands[i].description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: uiText(TextSize.small, color: ui.text3, height: 1.3),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// `.cchip`: an option half inside the field (folder, model).
class ComposerChip extends StatelessWidget {
  const ComposerChip(this.label, {super.key, this.icon, this.leading, this.onTap});

  final String label;
  final String? icon;

  /// In place of [icon]: a tool's logo…
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Pressable(
      onTap: onTap,
      pressedScale: .95,
      child: HoverBuilder(
        enabled: onTap != null,
        builder: (context, hover) => Surface(
          height: 24,
          // A shade darker under the mouse.
          color: hover ? Color.lerp(ui.thumb, ui.text, .06)! : ui.thumb,
          shadows: [...ui.shThumb, ui.cutout],
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 4)] else if (icon != null) ...[MikkyIcon(icon!, size: 13, color: ui.text), const SizedBox(width: 4)],
              Text(
                label,
                style: uiText(TextSize.caption, weight: FontWeight.w600, color: ui.text, height: 1),
              ),
              const SizedBox(width: 4),
              MikkyIcon('down', size: 11, color: ui.text2),
            ],
          ),
        ),
      ),
    );
  }
}
