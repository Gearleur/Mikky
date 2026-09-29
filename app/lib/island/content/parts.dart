import 'package:flutter/widgets.dart';

import '../../theme.dart';

/// Building blocks of the island content, as in the prototypes
/// (`btn`, `kbd`, `chip` in `ile-noir-et-blanc.html`).

TextStyle sansStyle(MikkyTheme t, {double size = 13, FontWeight weight = FontWeight.w400, Color? color}) => TextStyle(
      fontFamily: 'Geist',
      fontSize: size,
      fontWeight: weight,
      height: 1.35,
      letterSpacing: -.01 * size,
      color: color ?? t.foreground,
      decoration: TextDecoration.none,
    );

TextStyle monoStyle(MikkyTheme t, {double size = 11, FontWeight weight = FontWeight.w500, Color? color}) => TextStyle(
      fontFamily: 'Geist Mono',
      fontSize: size,
      fontWeight: weight,
      height: 1.4,
      color: color ?? t.secondary,
      decoration: TextDecoration.none,
    );

/// Colored status dot; glows on the dark theme only.
class IslandDot extends StatelessWidget {
  const IslandDot({super.key, required this.color, required this.theme, this.size = 7, this.glowRadius = 10});

  final Color color;
  final MikkyTheme theme;
  final double size;
  final double glowRadius;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: theme.glow ? [BoxShadow(color: color, blurRadius: glowRadius)] : null,
        ),
      );
}

/// Rounded "pill" button, with an optional keyboard hint (dark only).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.theme,
    this.primary = false,
    this.keyHint,
    this.onTap,
    this.height,
  });

  final String label;
  final MikkyTheme theme;
  final bool primary;
  final String? keyHint;
  final VoidCallback? onTap;

  /// Fixed height (portrait layout); otherwise sized by its padding.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final hint = t.keyHint;
    final fg = primary ? t.onPrimary : t.foreground;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? t.primary : t.button,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: sansStyle(t, size: 12.5, weight: primary ? FontWeight.w600 : FontWeight.w500, color: fg)),
            if (keyHint != null && hint != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Opacity(
                  opacity: .7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(color: hint),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(keyHint!, style: monoStyle(t, size: 10, color: fg).copyWith(height: 1.2)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small agent chip: dot, name and an optional mono value.
class AgentChip extends StatelessWidget {
  const AgentChip({super.key, required this.name, required this.color, required this.theme, this.value});

  final String name;
  final Color color;
  final MikkyTheme theme;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(color: t.faint, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IslandDot(color: color, theme: t, size: 6, glowRadius: 0),
          const SizedBox(width: 6),
          Text(name, style: sansStyle(t, size: 11.5, color: t.secondary)),
          if (value != null) ...[
            const SizedBox(width: 6),
            Opacity(opacity: .7, child: Text(value!, style: monoStyle(t, size: 11.5, color: t.foreground))),
          ],
        ],
      ),
    );
  }
}

/// Command or result in mono, in a soft block.
class CodeBlock extends StatelessWidget {
  const CodeBlock({super.key, required this.text, required this.theme, this.isError = false, this.maxLines = 1, this.size = 12});

  final String text;
  final MikkyTheme theme;
  final bool isError;
  final int maxLines;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.code,
        border: Border.all(color: t.codeBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        // A word joiner after each hyphen: a command wraps between words,
        // never inside a flag like "--release".
        maxLines > 1 ? text.replaceAll('-', '-\u2060') : text,
        maxLines: maxLines,
        softWrap: maxLines > 1,
        overflow: TextOverflow.ellipsis,
        style: monoStyle(t, size: size, weight: FontWeight.w400, color: isError ? t.error : t.foreground),
      ),
    );
  }
}

/// Thin progress bar.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, required this.color, required this.theme, this.thickness = 2});

  final double value;
  final Color color;
  final MikkyTheme theme;
  final double thickness;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(thickness),
        child: SizedBox(
          height: thickness,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: theme.faint),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: ColoredBox(color: color),
              ),
            ],
          ),
        ),
      );
}
