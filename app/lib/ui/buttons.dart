import 'package:flutter/widgets.dart';

import 'feedback.dart';
import 'icons.dart';
import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

enum ButtonKind {
  /// Black (white in dark), one per screen.
  primary,

  /// Grey, raised.
  secondary,

  /// No background; grey text.
  ghost,
}

/// `.btn`: a capsule, 44 px (small: 32 px), with an optional icon.
class MButton extends StatelessWidget {
  const MButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = ButtonKind.secondary,
    this.icon,
    this.small = false,
    this.block = false,
    this.loading = false,
  });

  final String label;

  /// Null: disabled (35 % opacity).
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final String? icon;
  final bool small;
  final bool block;

  /// A spinner before the label, and no press.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final (bg, gradient, fg, shadows) = switch (kind) {
      ButtonKind.primary => (ui.ink, null, ui.onInk, ui.shInk),
      ButtonKind.secondary => (null, ui.control, ui.text, [ui.highlight, ...ui.shCtl]),
      ButtonKind.ghost => (null, null, ui.text2, const <CssShadow>[]),
    };
    final enabled = onPressed != null && !loading;
    final text = uiText(small ? 13 : 15, weight: FontWeight.w600, color: fg, height: 1, tracking: small ? 0 : -.005);
    Widget content = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[Spinner(color: fg), const SizedBox(width: 8)],
        if (icon != null && !loading) ...[
          Transform.translate(
            offset: const Offset(-3, 0),
            child: MikkyIcon(icon!, size: 18, color: fg),
          ),
          const SizedBox(width: 5),
        ],
        Text(label, style: text, maxLines: 1),
      ],
    );
    content = Surface(
      color: bg,
      gradient: gradient,
      shadows: shadows,
      height: small ? 32 : 44,
      padding: EdgeInsets.symmetric(horizontal: small ? 14 : 22),
      child: DefaultTextStyle(style: text, child: content),
    );
    return Opacity(
      opacity: onPressed == null && !loading ? .35 : 1,
      child: Pressable(onTap: onPressed, enabled: enabled, child: content),
    );
  }
}

/// `.round`: one action as an icon. Sizes: 40 (default), 34 (sm), 26 (xs),
/// 46 (the home's new-agent button), 32 (inside the field).
class RoundButton extends StatelessWidget {
  const RoundButton(this.icon, {super.key, this.onPressed, this.size = 40, this.ink = false, this.ghost = false, this.iconSize, this.tooltip});

  final String icon;
  final VoidCallback? onPressed;
  final double size;

  /// Black (white in dark): the main action.
  final bool ink;

  /// No background (the mic in the field).
  final bool ghost;
  final double? iconSize;
  final String? tooltip;

  static double iconFor(double size) => switch (size) {
    >= 46 => 21,
    >= 40 => 20,
    >= 34 => 18,
    >= 32 => 17,
    _ => 14,
  };

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final fg = ink ? ui.onInk : (ghost ? ui.text2 : ui.text);
    return Semantics(
      button: true,
      label: tooltip,
      child: Pressable(
        onTap: onPressed,
        pressedScale: .9,
        child: Surface(
          width: size,
          height: size,
          color: ink ? ui.ink : null,
          gradient: ink || ghost ? null : ui.control,
          shadows: ink ? ui.shInk : (ghost ? const [] : [ui.highlight, ...ui.shCtl]),
          child: Center(
            child: MikkyIcon(icon, size: iconSize ?? iconFor(size), color: fg),
          ),
        ),
      ),
    );
  }
}

/// `.bar`: a group of actions on a translucent capsule.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Surface(
      color: ui.raise,
      shadows: [CssShadow(0, 0, 0, ui.hlEdge, spread: 1, inset: true), ...ui.shBar],
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 10), children[i]],
        ],
      ),
    );
  }
}
