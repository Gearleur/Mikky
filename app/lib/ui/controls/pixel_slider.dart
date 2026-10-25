import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../foundation/motion.dart';
import '../foundation/tokens.dart';
import '../pixels/pixel_cursor.dart';
import '../pixels/pixel_fx.dart';

/// A continuous slider with the page navigation's blue pixel star.
/// Drag follows the pointer; clicks and keyboard changes glide to the
/// new value. The animation stops completely at rest.
class PixelSlider extends StatefulWidget {
  const PixelSlider({super.key, required this.value, this.onChanged, this.label = 'Volume'});

  final double value;
  final ValueChanged<double>? onChanged;
  final String label;

  static const height = 24.0, star = 13.0, inset = 8.0;

  @override
  State<PixelSlider> createState() => _PixelSliderState();
}

class _PixelSliderState extends State<PixelSlider> with SingleTickerProviderStateMixin {
  late final _glide = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);
  final _focus = FocusNode();
  late double _from = widget.value;
  bool _dragging = false, _highlight = false;
  static const _ease = Cubic(.45, 0, .2, 1);

  double _at(double value, double t) => _from + (value - _from) * _ease.transform(t);
  double _step(int delta) => (widget.value + delta * .05).clamp(0.0, 1.0);
  String _percent(double value) => '${(value * 100).round()} pour cent';

  @override
  void didUpdateWidget(PixelSlider old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    _from = _at(old.value, _glide.value);
    if (_dragging || Motion.reduced(context)) {
      _glide.value = 1;
    } else {
      _glide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (widget.onChanged == null || (event is! KeyDownEvent && event is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final value = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowDown => _step(-1),
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowUp => _step(1),
      LogicalKeyboardKey.home => 0.0,
      LogicalKeyboardKey.end => 1.0,
      _ => null,
    };
    if (value == null) return KeyEventResult.ignored;
    widget.onChanged!(value);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final enabled = widget.onChanged != null;
    return Semantics(
      label: widget.label,
      slider: true,
      enabled: enabled,
      value: _percent(widget.value),
      increasedValue: enabled ? _percent(_step(1)) : null,
      decreasedValue: enabled ? _percent(_step(-1)) : null,
      onIncrease: enabled ? () => widget.onChanged!(_step(1)) : null,
      onDecrease: enabled ? () => widget.onChanged!(_step(-1)) : null,
      excludeSemantics: true,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _key,
        child: FocusableActionDetector(
          focusNode: _focus,
          enabled: enabled,
          onShowFocusHighlight: (value) => setState(() => _highlight = value),
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
            child: LayoutBuilder(
              builder: (context, box) {
                void change(Offset at) {
                  final travel = box.maxWidth - 2 * PixelSlider.inset;
                  if (travel <= 0) return;
                  _focus.requestFocus();
                  widget.onChanged?.call(((at.dx - PixelSlider.inset) / travel).clamp(0.0, 1.0));
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: enabled ? (event) => change(event.localPosition) : null,
                  onHorizontalDragStart: enabled
                      ? (event) {
                          _dragging = true;
                          change(event.localPosition);
                        }
                      : null,
                  onHorizontalDragUpdate: enabled ? (event) => change(event.localPosition) : null,
                  onHorizontalDragEnd: enabled ? (_) => _dragging = false : null,
                  onHorizontalDragCancel: () => _dragging = false,
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _glide,
                      builder: (_, _) {
                        final t = _glide.value;
                        final value = _at(widget.value, t);
                        final behind = _at(widget.value, (t - .08).clamp(0.0, 1.0));
                        return CustomPaint(
                          size: Size(box.maxWidth, PixelSlider.height),
                          painter: _PixelSliderPainter(
                            value: value,
                            trail: t < 1 ? (value - behind) * (box.maxWidth - 2 * PixelSlider.inset) : 0,
                            palette: enabled ? PixelFxPalette.signatureBlue.onWindow(ui) : PixelFxPalette.grey.on(ui),
                            track: ui.text2.withValues(alpha: enabled ? .25 : .12),
                            focus: _highlight ? ui.ink : null,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PixelSliderPainter extends CustomPainter {
  const _PixelSliderPainter({
    required this.value,
    required this.trail,
    required this.palette,
    required this.track,
    this.focus,
  });

  final double value, trail;
  final PixelFxPalette palette;
  final Color track;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final x = PixelSlider.inset + value * (size.width - 2 * PixelSlider.inset);
    final cy = size.height / 2;
    final paint = Paint()..color = track;
    for (var dx = PixelSlider.inset; dx <= size.width - PixelSlider.inset; dx += 7) {
      if ((dx - x).abs() < PixelSlider.star / 2 + 1) continue;
      paint.color = dx < x ? palette.levels[1].withValues(alpha: .45) : track;
      canvas.drawRect(Rect.fromCenter(center: Offset(dx, cy), width: 2, height: 2), paint);
    }
    if (focus != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
        paint
          ..color = focus!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    paintPixelCursor(canvas, center: Offset(x, cy), size: PixelSlider.star, palette: palette, trail: trail);
  }

  @override
  bool shouldRepaint(_PixelSliderPainter old) =>
      old.value != value || old.trail != trail || old.palette != palette || old.track != track || old.focus != focus;
}
