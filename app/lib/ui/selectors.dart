import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

enum SegmentSize {
  /// `.seg`: 38 px buttons, at least 260 px wide.
  normal,

  /// `.seg.xs`: 28 px buttons.
  xs,

  /// `.cseg`: 22 px, half in the field (Suivi | Chat).
  field,
}

/// `.seg`: a choice between a few options; the white capsule slides with
/// a spring (420 / 0.78) and stretches with its speed (≤ 10 px), like jelly.
/// All options are as wide as the widest (`grid-auto-columns: 1fr`).
class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.selected, this.onChanged, this.size = SegmentSize.normal});

  final List<String> options;
  final int selected;
  final ValueChanged<int>? onChanged;
  final SegmentSize size;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final (pad, h, padX, font, minWidth) = switch (size) {
      SegmentSize.normal => (4.0, 38.0, 18.0, 14.5, 260.0),
      SegmentSize.xs => (3.0, 28.0, 11.0, 12.5, 0.0),
      SegmentSize.field => (2.0, 22.0, 11.0, 11.5, 0.0),
    };
    final scale = MediaQuery.textScalerOf(context);
    var col = 0.0;
    for (final o in options) {
      final tp = TextPainter(text: TextSpan(text: o, style: uiText(font, weight: FontWeight.w600, height: 1)), textDirection: TextDirection.ltr, textScaler: scale)..layout();
      col = col > tp.width ? col : tp.width;
    }
    col += padX * 2;
    if (col * options.length < minWidth - pad * 2) col = (minWidth - pad * 2) / options.length;
    final shadows = size == SegmentSize.field ? [CssShadow(0, 0, 0, ui.island, spread: 3)] : ui.inset;
    return Surface(
      color: ui.track,
      shadows: shadows,
      padding: EdgeInsets.all(pad),
      child: SizedBox(
        width: col * options.length,
        height: h,
        child: Stack(children: [
          SpringValue(
            target: selected * col,
            spring: Motion.thumb,
            builder: (context, x, v) {
              final stretch = (v.abs() * .012).clamp(0.0, 10.0);
              return Positioned(
                left: x - (v > 0 ? stretch : 0),
                top: 0,
                bottom: 0,
                width: col + stretch,
                child: Surface(color: ui.thumb, shadows: ui.shThumb),
              );
            },
          ),
          Row(children: [
            for (var i = 0; i < options.length; i++)
              SizedBox(
                width: col,
                height: h,
                child: MouseRegion(
                  cursor: onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onChanged == null ? null : () => onChanged!(i),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: uiText(font, weight: FontWeight.w600, height: 1, color: i == selected ? ui.text : ui.text2),
                        child: Text(options[i], maxLines: 1),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// `.switch`: 50 × 30; the knob slides with a bounce (380 ms) and grows
/// from 24 to 30 px while pressed.
class MSwitch extends StatefulWidget {
  const MSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<MSwitch> createState() => _MSwitchState();
}

class _MSwitchState extends State<MSwitch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final on = widget.value;
    final reduced = Motion.reduced(context);
    final knobW = _pressed ? 30.0 : 24.0;
    final left = on ? (_pressed ? 17.0 : 23.0) : 3.0;
    return MouseRegion(
      cursor: widget.onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onChanged == null ? null : () => widget.onChanged!(!on),
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: on ? ui.ink : ui.track),
          duration: Duration(milliseconds: reduced ? 1 : 250),
          builder: (context, track, _) => Surface(
            width: 50,
            height: 30,
            color: track,
            shadows: ui.inset,
            child: Stack(children: [
              AnimatedPositioned(
                duration: Duration(milliseconds: reduced ? 1 : 380),
                curve: const Cubic(.34, 1.5, .64, 1),
                left: left,
                top: 3,
                width: knobW,
                height: 24,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: on ? ui.onInk : ui.knob),
                  duration: Duration(milliseconds: reduced ? 1 : 250),
                  builder: (context, knob, _) => Surface(color: knob, shadows: ui.shThumb),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// `.chip`: a small capsule (32 px). [on]: black; [soft]: in a hollow,
/// like a folder picker; [count]: the grey number after the label.
class MChip extends StatelessWidget {
  const MChip(this.label, {super.key, this.on = false, this.soft = false, this.count, this.icon, this.trailingIcon, this.onTap});

  final String label;
  final bool on;
  final bool soft;
  final int? count;
  final String? icon;
  final String? trailingIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final fg = on ? ui.onInk : ui.text;
    final style = uiText(13, weight: soft ? FontWeight.w500 : FontWeight.w600, color: fg, height: 1);
    return Pressable(
      onTap: onTap,
      pressedScale: .95,
      child: Surface(
        height: 32,
        color: on ? ui.ink : (soft ? ui.track : null),
        gradient: on || soft ? null : ui.control,
        shadows: on ? ui.shInk : (soft ? ui.inset : [ui.highlight, ...ui.shCtl]),
        padding: EdgeInsets.symmetric(horizontal: soft ? 10 : 13),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[MikkyIcon(icon!, size: 15, color: fg), const SizedBox(width: 6)],
          Text(label, style: style),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('$count', style: uiText(13, weight: FontWeight.w600, height: 1, tabular: true, color: on ? fg.withValues(alpha: .6) : ui.text2)),
          ],
          if (trailingIcon != null) ...[const SizedBox(width: 4), MikkyIcon(trailingIcon!, size: 13, color: ui.text2)],
        ]),
      ),
    );
  }
}
