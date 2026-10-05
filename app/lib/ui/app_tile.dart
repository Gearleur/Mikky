import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'motion.dart';
import 'pixel_fx.dart';
import 'status.dart';
import 'surface.dart';
import 'tokens.dart';

/// An app on the home (2026-10-02, mockups `docs/notch_haut/`): a neutral
/// tile, white fading to grey, its drawing to come. One radius for every
/// size (27 % of the side), the light top edge and a hairline of the
/// raised controls; under the mouse it rises 2 px and its shadow grows;
/// pressed, it shrinks like every button.
class AppTile extends StatefulWidget {
  const AppTile({super.key, this.size = 64, this.width, this.label, this.onTap, this.child, this.status});

  /// Its height, and its width when square.
  final double size;

  /// Wider than high: the notch's apps, with their words on the tile
  /// (2026-10-05). Null: square.
  final double? width;

  /// Read by screen readers.
  final String? label;
  final VoidCallback? onTap;

  /// The app's drawing, later; empty for now.
  final Widget? child;

  /// Trial: the agent's state in a small disc on the corner.
  final UiStatus? status;

  static double radiusFor(double size) => (size * .27 * 2).roundToDouble() / 2;

  @override
  State<AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<AppTile> {
  bool _hover = false, _keyboard = false;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final s = widget.size, r = AppTile.radiusFor(s);
    final on = widget.onTap != null;
    final (color, gradient, shadows) = _face(ui, TileLookScope.of(context));
    final face = Surface(
      width: widget.width ?? s,
      height: s,
      radius: r,
      color: color,
      gradient: gradient,
      shadows: [...shadows, if (_keyboard) ...ui.focusRing],
      child: widget.child,
    );
    final status = widget.status;
    // The state's pastille: 22 on the 64 px tiles, 16 on the small ones.
    final pin = s >= 60 ? 22.0 : 16.0;
    final tile = status == null
        ? face
        : Stack(
            clipBehavior: Clip.none,
            children: [
              face,
              Positioned(
                right: -pin * .23,
                top: -pin * .23,
                child: Surface(
                  width: pin,
                  height: pin,
                  color: ui.thumb,
                  shadows: [...ui.shCtl, CssShadow(0, 0, 0, ui.line, spread: .7, inset: true)],
                  child: Center(child: StatusFx(status, size: pin >= 22 ? 14 : 10)),
                ),
              ),
            ],
          );
    final lifted = TweenAnimationBuilder<double>(
      tween: Tween(end: _hover && on ? 1 : 0),
      duration: Motion.of(context, Motion.hover),
      curve: Motion.enter,
      child: tile,
      builder: (context, t, tile) => Transform.translate(
        offset: Offset(0, -2 * t),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The bigger shadow of a lifted tile, faded in under it.
            if (t > 0)
              Positioned.fill(
                child: Opacity(opacity: t, child: Surface(radius: r, shadows: ui.shBar)),
              ),
            tile!,
          ],
        ),
      ),
    );
    return Semantics(
      button: on,
      label: widget.label,
      child: Focus(
        canRequestFocus: on,
        onFocusChange: (f) {
          final keyboard = f && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
          if (keyboard != _keyboard) setState(() => _keyboard = keyboard);
        },
        onKeyEvent: (_, e) {
          if (on && e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Pressable(
            onTap: widget.onTap,
            pressedScale: .95,
            child: RepaintBoundary(child: lifted),
          ),
        ),
      ),
    );
  }
}

/// The tile that starts a task (2026-10-02): an app's tile with « + »,
/// after the apps, in the first free place. Wide (the notch): « + » where
/// an app has its sign, and « Nouvelle tâche ».
class AddTile extends StatelessWidget {
  const AddTile({super.key, this.size = 64, this.width, this.onTap});

  final double size;
  final double? width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final w = width;
    return AppTile(
      size: size,
      width: w,
      label: 'Nouvelle tâche',
      onTap: onTap,
      child: w == null
          ? Center(child: MikkyIcon('plus', size: (size * .3).roundToDouble(), color: ui.text2, stroke: 2))
          : Padding(
              padding: const EdgeInsets.only(left: 11, right: 12),
              child: Row(children: [
                SizedBox(width: 16, child: Center(child: MikkyIcon('plus', size: 15, color: ui.text2, stroke: 2))),
                const SizedBox(width: 9),
                Text('Nouvelle tâche', style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text2)),
              ]),
            ),
    );
  }
}

/// A free place on a page of apps (2026-10-02): a small hollow token in
/// its middle, waiting for an app (the hollow of our tracks, not a tile).
class AppSlot extends StatelessWidget {
  const AppSlot({super.key, this.size = 64, this.width});

  final double size;

  /// A wide place (the notch); null: square.
  final double? width;

  /// The token's side.
  static double tokenFor(double size) => (size * .16).clamp(9.0, 16.0).roundToDouble();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final t = tokenFor(size);
    return ExcludeSemantics(
      child: SizedBox(
        width: width ?? size,
        height: size,
        child: Center(child: Surface(width: t, height: t, color: ui.track, shadows: ui.inset)),
      ),
    );
  }
}

/// Trials for the tiles in dark (2026-10-05: the raised controls' grey
/// « fait cheap, pas premium »); in light, the tile stays as it is.
enum TileLook {
  /// The raised controls' gradient (#26262A → #1B1B1E), as until now.
  control,

  /// Near black, a fine light rim and a sheen on top: polished stone.
  obsidian,

  /// A faint white veil on the black, a fine rim: smoked glass.
  smoke,

  /// A deeper grey than the controls, a stronger sheen on top.
  soft,

  /// The island's black, only a fine light outline.
  outline,
}

/// The [TileLook] of the tiles under it (the boards' trials); none: the
/// raised controls' gradient.
class TileLookScope extends InheritedWidget {
  const TileLookScope({super.key, required this.look, required super.child});

  final TileLook look;

  static TileLook of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TileLookScope>()?.look ?? TileLook.control;

  @override
  bool updateShouldNotify(TileLookScope old) => old.look != look;
}

/// A tile's face: its color or gradient, and its shadows.
(Color?, Gradient?, List<CssShadow>) _face(MikkyUi ui, TileLook look) {
  LinearGradient down(Color a, Color b) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [a, b]);
  CssShadow rim(Color c, [double spread = .8]) => CssShadow(0, 0, 0, c, spread: spread, inset: true);
  CssShadow sheen(Color c) => CssShadow(0, 1, 0, c, inset: true);
  if (ui.isLight || look == TileLook.control) return (null, ui.tile, [...ui.shThumb, ui.highlight, rim(ui.line)]);
  return switch (look) {
    TileLook.obsidian => (
      null,
      down(const Color(0xFF151517), const Color(0xFF0C0C0E)),
      [const CssShadow(0, 2, 8, Color(0x80000000)), sheen(const Color(0x17FFFFFF)), rim(const Color(0x14FFFFFF))],
    ),
    TileLook.smoke => (const Color(0x0DFFFFFF), null, [sheen(const Color(0x0FFFFFFF)), rim(const Color(0x17FFFFFF))]),
    TileLook.soft => (
      null,
      down(const Color(0xFF1F1F22), const Color(0xFF131315)),
      [...ui.shThumb, sheen(const Color(0x24FFFFFF)), rim(const Color(0x0DFFFFFF))],
    ),
    TileLook.outline => (const Color(0xFF0A0A0B), null, [rim(const Color(0x1FFFFFFF), 1)]),
    TileLook.control => (null, ui.tile, const <CssShadow>[]),
  };
}
