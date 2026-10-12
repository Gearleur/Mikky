import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../foundation/icons.dart';
import '../foundation/motion.dart';
import '../foundation/status.dart';
import '../foundation/surface.dart';
import '../foundation/tokens.dart';
import '../pixels/pixel_fx.dart';

/// Readable text on the opaque white application tile, in either UI theme.
class AppTileInk extends InheritedWidget {
  const AppTileInk({super.key, required this.text, required this.secondary, required super.child});

  final Color text, secondary;

  static AppTileInk? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppTileInk>();

  @override
  bool updateShouldNotify(AppTileInk old) => text != old.text || secondary != old.secondary;
}

/// An opaque pure-white tile with a quiet edge and short shadow.
/// Corners use 27 % of its height; it grows 5 % on hover and shrinks
/// when pressed. Shared by the app and the boards.
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

  /// The application's drawing or its sign and words.
  final Widget? child;

  /// The agent's state in a small disc on the corner.
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
    final status = widget.status;
    // The state's pastille: 22 on the 64 px tiles, 16 on the small ones.
    final pin = s >= 60 ? 22.0 : 16.0;
    final badge = status == null
        ? null
        : Surface(
            width: pin,
            height: pin,
            color: ui.thumb,
            shadows: [...ui.shCtl, CssShadow(0, 0, 0, ui.line, spread: .7, inset: true)],
            child: Center(child: StatusFx(status, size: pin >= 22 ? 14 : 10)),
          );
    final enlarged = TweenAnimationBuilder<double>(
      tween: Tween(end: _hover && on ? 1 : 0),
      duration: Motion.of(context, Motion.hover),
      curve: Motion.enter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Surface(
            width: widget.width ?? s,
            height: s,
            radius: r,
            color: ui.tileColor,
            shadows: [...ui.tileShadows, if (_keyboard) CssShadow(0, 0, 0, ui.ink, spread: 1.5)],
            child: ClipRRect(
              borderRadius: BorderRadius.circular(r),
              child: MikkyUiTheme(
                ui: MikkyUi.light,
                child: AppTileInk(
                  text: ui.tileText,
                  secondary: ui.tileText2,
                  child: widget.child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          if (badge != null) Positioned(right: -pin * .23, top: -pin * .23, child: badge),
        ],
      ),
      builder: (context, t, content) => Transform.scale(scale: 1 + .05 * t, child: content),
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
          if (on &&
              e is KeyDownEvent &&
              (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.space)) {
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
            child: RepaintBoundary(child: enlarged),
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
    return AppTile(
      size: size,
      width: width,
      label: 'Nouvelle tâche',
      onTap: onTap,
      child: _AddTileContent(size: size, wide: width != null),
    );
  }
}

/// Resolves the same readable colours as the other white tile contents.
class _AddTileContent extends StatelessWidget {
  const _AddTileContent({required this.size, required this.wide});

  final double size;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final color = AppTileInk.maybeOf(context)?.secondary ?? MikkyUi.of(context).text2;
    return !wide
        ? Center(
            child: MikkyIcon('plus', size: (size * .3).roundToDouble(), color: color, stroke: 2),
          )
        : Padding(
            padding: const EdgeInsets.only(left: 11, right: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: Center(child: MikkyIcon('plus', size: 15, color: color, stroke: 2)),
                ),
                const SizedBox(width: 9),
                Text(
                  'Nouvelle tâche',
                  style: uiText(TextSize.small, weight: FontWeight.w600, color: color),
                ),
              ],
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
        child: Center(
          child: Surface(width: t, height: t, color: ui.track, shadows: ui.inset),
        ),
      ),
    );
  }
}
