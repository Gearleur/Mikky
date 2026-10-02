import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
  const AppTile({super.key, this.size = 64, this.label, this.onTap, this.child, this.status});

  final double size;

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
    final face = Surface(
      width: s,
      height: s,
      radius: r,
      gradient: ui.tile,
      shadows: [
        ...ui.shThumb,
        ui.highlight,
        CssShadow(0, 0, 0, ui.line, spread: .8, inset: true),
        if (_keyboard) ...ui.focusRing,
      ],
      child: widget.child,
    );
    final status = widget.status;
    final tile = status == null
        ? face
        : Stack(
            clipBehavior: Clip.none,
            children: [
              face,
              Positioned(
                right: -5,
                top: -5,
                child: Surface(
                  width: 22,
                  height: 22,
                  color: ui.thumb,
                  shadows: [...ui.shCtl, CssShadow(0, 0, 0, ui.line, spread: .7, inset: true)],
                  child: Center(child: StatusFx(status, size: 14)),
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
