import 'dart:math' as math;

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

/// What the selector looks like: at rest (flat), under the mouse (grey),
/// raised (pressed, or its menu open: the relief of an answer).
enum _Look { rest, hover, raised }

/// « Choisir l'environnement » (redone 2026-10-02): the name and the
/// settings' grey star, flat; grey under the mouse; pressed or menu open,
/// the relief of an answer, and back to flat as soon as the menu is gone.
/// Both the name and the star open our floating menu out of the star. A
/// new choice slides in from below, the old one out above. As wide as
/// the longest name: it never moves. The focus ring only after the
/// keyboard. [menuWithin]: the enclosing window, below its Overlay, used
/// as the menu's bounds.
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

  /// At least this wide: its menu, as wide as it, fits the names and
  /// their check.
  static const minWidth = 100.0;

  @override
  State<EnvironmentSelector> createState() => _EnvironmentSelectorState();
}

class _EnvironmentSelectorState extends State<EnvironmentSelector> {
  final _star = GlobalKey();
  final _focus = FocusNode(debugLabel: 'environment');
  bool _open = false, _pressed = false, _hover = false, _focused = false;

  _Look get _look => _open || _pressed ? _Look.raised : (_hover ? _Look.hover : _Look.rest);

  /// A ring only when the keyboard brought the focus here.
  bool get _ring => _focused && KeyboardUse.last && !_open;

  @override
  void initState() {
    super.initState();
    FloatingMenu.track();
    KeyboardUse.start();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openMenu() async {
    if (_open) return;
    // The menu unfolds straight out of the whole selector, as wide as it:
    // down, or up when there is no room below — never off to the side
    // (user, 2026-10-02: at the right it went off to the left).
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final from = box.localToGlobal(Offset.zero) & box.size;
    setState(() => _open = true);
    final id = await showFloatingMenu(
      widget.menuWithin,
      environmentMenuEntries(widget.selected),
      from: from,
      width: from.width,
    );
    if (!mounted) return;
    // Back to flat, whatever happened while the menu was open (the mouse
    // left, the press ended under the menu).
    setState(() {
      _open = false;
      _pressed = false;
      _hover = false;
    });
    if (id != null) {
      final next = MikkyEnvironment.values[id - 1];
      if (next != widget.selected) widget.onChanged(next);
    }
    // The keyboard comes back here, to go on with it.
    if (KeyboardUse.last) _focus.requestFocus();
  }

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final style = uiText(TextSize.label, weight: FontWeight.w600, height: 1, color: ui.text);
    final width = math.max(EnvironmentSelector.minWidth, EnvironmentSelector._padLeft + _widestLabel(style, MediaQuery.textScalerOf(context)) + 4 + EnvironmentSelector._star);
    final look = _look;
    final raised = look == _Look.raised;
    final clear = ui.thumb.withValues(alpha: 0);
    return RepaintBoundary(
      child: Focus(
        focusNode: _focus,
        onFocusChange: (f) => setState(() => _focused = f),
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
                child: AnimatedScale(
                  // A little smaller while pressed, back with a slight bounce.
                  scale: _pressed ? .97 : 1,
                  duration: _pressed ? Motion.pressDown : Motion.pressUp,
                  curve: _pressed ? Curves.easeOut : Motion.release,
                  child: AnimatedContainer(
                    duration: Motion.of(context, raised ? Motion.pressDown : Motion.fade),
                    curve: Motion.enter,
                    width: width,
                    height: EnvironmentSelector.height,
                    padding: const EdgeInsets.only(left: EnvironmentSelector._padLeft, right: 1),
                    decoration: BoxDecoration(
                      color: switch (look) {
                        _Look.raised => ui.thumb,
                        _Look.hover => ui.hover,
                        _Look.rest => clear,
                      },
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(
                        color: _ring ? ui.ink : (raised ? ui.line : ui.line.withValues(alpha: 0)),
                        width: _ring ? 1.5 : .8,
                      ),
                      boxShadow: [
                        for (final s in ui.shThumb)
                          if (!s.inset) s.box.copyWith(color: raised ? s.color : s.color.withValues(alpha: 0)),
                      ],
                    ),
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          Expanded(child: _Name(widget.selected.label, style: style)),
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
      ),
    );
  }
}

/// The name: a new one slides in from below as the old one leaves above,
/// both fading, clipped to the line.
class _Name extends StatelessWidget {
  const _Name(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedSwitcher(
      duration: Motion.of(context, Motion.slide),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.leave,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
      transitionBuilder: (child, t) {
        final incoming = child.key == ValueKey(text);
        final slide = Tween(begin: Offset(0, incoming ? .9 : -.9), end: Offset.zero).animate(t);
        return FadeTransition(opacity: t, child: SlideTransition(position: slide, child: child));
      },
      child: Text(text, key: ValueKey(text), maxLines: 1, style: style),
    ),
  );
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
