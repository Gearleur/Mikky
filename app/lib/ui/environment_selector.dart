import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../overlay/overlay_channel.dart';
import 'buttons.dart';
import 'floating_menu.dart';
import 'motion.dart';
import 'tokens.dart';

/// Where an agent runs. Local and WSL work today; VPS and Cloud are only
/// drawn (design.md §7, « Choisir l'environnement »).
enum MikkyEnvironment {
  local('Local'),
  wsl('WSL'),
  vps('VPS'),
  cloud('Cloud');

  const MikkyEnvironment(this.label);
  final String label;
}

List<MenuEntry> environmentMenuEntries(MikkyEnvironment selected) => [
  for (final environment in MikkyEnvironment.values)
    MenuEntry(
      environment.index + 1,
      environment.label,
      checked: environment == selected,
    ),
];

/// « Choisir l'environnement » (2026-10-02, from « Choisir le lieu »): the
/// name, flat, and the settings' grey star; both open our floating menu
/// from the star. Grey under the mouse, the relief of an answer while
/// pressed or open. As wide as the longest name, so it never moves when
/// the choice changes. [menuWithin]: the enclosing window, below its
/// Overlay, used as the menu's bounds.
class EnvironmentSelector extends StatefulWidget {
  const EnvironmentSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.menuWithin,
  });

  final MikkyEnvironment selected;
  final ValueChanged<MikkyEnvironment> onChanged;
  final BuildContext menuWithin;

  static const height = 36.0;

  /// The star's round zone, at the right end.
  static const _star = 34.0;
  static const _padLeft = 13.0;

  /// Narrow: four short names.
  static const menuWidth = 176.0;

  @override
  State<EnvironmentSelector> createState() => _EnvironmentSelectorState();
}

class _EnvironmentSelectorState extends State<EnvironmentSelector> {
  final _star = GlobalKey();
  final _focus = FocusNode();
  bool _open = false, _pressed = false, _hover = false, _keyboardFocus = false;

  @override
  void initState() {
    super.initState();
    FloatingMenu.track();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openMenu() async {
    if (_open) return;
    _focus.requestFocus();
    // Label and star both open from the same settings star.
    final star = _star.currentContext;
    if (star != null) FloatingMenu.pressed(star);
    setState(() => _open = true);
    final id = await showFloatingMenu(
      widget.menuWithin,
      environmentMenuEntries(widget.selected),
      width: EnvironmentSelector.menuWidth,
    );
    if (!mounted) return;
    setState(() {
      _open = false;
      _pressed = false;
    });
    // Back to the selector for the keyboard; the ring shows only for it.
    _focus.requestFocus();
    if (id != null) {
      final next = MikkyEnvironment.values[id - 1];
      if (next != widget.selected) widget.onChanged(next);
    }
  }

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  // The ring only for the keyboard: a mouse choice leaves no outline.
  void _focusChanged(bool focused) {
    final keyboard = focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (keyboard != _keyboardFocus) setState(() => _keyboardFocus = keyboard);
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final raised = _open || _pressed;
    final label = uiText(TextSize.label, weight: FontWeight.w600, height: 1);
    final width = EnvironmentSelector._padLeft + _widestLabel(label, MediaQuery.textScalerOf(context)) + 4 + EnvironmentSelector._star;
    return RepaintBoundary(
      child: Focus(
        focusNode: _focus,
        onFocusChange: _focusChanged,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.arrowDown)) {
            _openMenu();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          button: true,
          label: 'Choisir l’environnement',
          value: widget.selected.label,
          onTap: _openMenu,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: Listener(
              onPointerDown: (event) {
                if (event.buttons == kPrimaryButton) _press(true);
              },
              onPointerUp: (_) => _press(false),
              onPointerCancel: (_) => _press(false),
              child: GestureDetector(
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTap: _openMenu,
                child: AnimatedContainer(
                  duration: Motion.of(context, raised ? Motion.pressDown : Motion.hover),
                  width: width,
                  height: EnvironmentSelector.height,
                  padding: const EdgeInsets.only(left: EnvironmentSelector._padLeft, right: 1),
                  decoration: BoxDecoration(
                    color: raised ? ui.thumb : (_hover ? ui.hover : ui.thumb.withValues(alpha: 0)),
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(
                      color: raised ? ui.line : (_keyboardFocus ? ui.ink : ui.line.withValues(alpha: 0)),
                      width: _keyboardFocus && !raised ? 1.5 : .8,
                    ),
                    boxShadow: [
                      for (final s in ui.shThumb)
                        if (!s.inset) s.box.copyWith(color: raised ? s.color : s.color.withValues(alpha: 0)),
                    ],
                  ),
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.selected.label,
                            maxLines: 1,
                            style: label.copyWith(color: ui.text),
                          ),
                        ),
                        RoundButton.menu(
                          key: _star,
                          size: EnvironmentSelector._star,
                          tooltip: 'Choisir l’environnement',
                          onPressed: _openMenu,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final Map<(double, double), double> _widest = {};

/// The longest name, measured once per text size.
double _widestLabel(TextStyle style, TextScaler scaler) => _widest[(style.fontSize!, scaler.scale(1))] ??= () {
  var w = 0.0;
  for (final e in MikkyEnvironment.values) {
    final p = TextPainter(text: TextSpan(text: e.label, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
    if (p.width > w) w = p.width;
    p.dispose();
  }
  return w.ceilToDouble();
}();
