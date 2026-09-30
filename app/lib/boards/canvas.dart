import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ui/motion.dart';
import '../ui/tokens.dart';

/// A board of the design boards: a name in the sidebar, and its sections.
class BoardSpec {
  const BoardSpec(this.name, this.note, this.sections);

  final String name;

  /// One line under the name.
  final String note;

  /// Built in the theme of the band that shows it.
  final List<BoardSection> Function(BuildContext context) sections;
}

/// A row of frames on a board, with its title.
class BoardSection extends StatelessWidget {
  const BoardSection({super.key, required this.title, this.note, required this.frames});

  final String title;
  final String? note;
  final List<Widget> frames;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: uiText(22, weight: FontWeight.w600, color: ui.text, tracking: -.01)),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Text(note!, style: uiText(13, color: ui.text2, height: 1.45)),
              ),
            ),
          const SizedBox(height: 22),
          Wrap(spacing: 48, runSpacing: 44, crossAxisAlignment: WrapCrossAlignment.start, children: frames),
        ],
      ),
    );
  }
}

/// One frame on a board: its name, a line about it, then the thing itself,
/// live (it moves, it can be clicked).
class BoardFrame extends StatelessWidget {
  const BoardFrame({super.key, required this.label, this.note, required this.child, this.width});

  final String label;
  final String? note;
  final Widget child;

  /// Width of the text above; the child keeps its own size.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: uiText(13, weight: FontWeight.w600, color: ui.text2)),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: SizedBox(width: width ?? 320, child: Text(note!, style: uiText(11.5, color: ui.text3, height: 1.4))),
          ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// A canvas as in Figma: the wheel scrolls it (Shift: sideways), Ctrl and
/// the wheel zoom around the mouse, dragging the empty space moves it.
/// Frames on it stay live.
class BoardCanvas extends StatefulWidget {
  const BoardCanvas({super.key, required this.child, required this.background, this.onScale});

  final Widget child;
  final Color background;

  /// Told when the zoom changes (for the percentage).
  final ValueChanged<double>? onScale;

  @override
  State<BoardCanvas> createState() => BoardCanvasState();
}

class BoardCanvasState extends State<BoardCanvas> {
  static const _start = Offset(48, 40);
  Offset _offset = _start;
  double _scale = 1;

  double get scale => _scale;

  void reset() {
    setState(() {
      _offset = _start;
      _scale = 1;
    });
    widget.onScale?.call(1);
  }

  void zoomBy(double factor, [Offset? around]) {
    final box = context.findRenderObject() as RenderBox?;
    final p = around ?? (box == null ? Offset.zero : box.size.center(Offset.zero));
    final next = (_scale * factor).clamp(.25, 3.0);
    setState(() {
      _offset = p - (p - _offset) * (next / _scale);
      _scale = next;
    });
    widget.onScale?.call(next);
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Something inside that scrolls (a page's thread) gets the wheel first.
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final s = e as PointerScrollEvent;
      final keys = HardwareKeyboard.instance;
      if (keys.isControlPressed) {
        zoomBy(s.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1, s.localPosition);
      } else {
        final d = keys.isShiftPressed ? Offset(s.scrollDelta.dy, 0) : s.scrollDelta;
        setState(() => _offset -= d);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _signal,
    child: ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() => _offset += d.delta),
              child: MouseRegion(cursor: SystemMouseCursors.grab, child: ColoredBox(color: widget.background)),
            ),
          ),
          Positioned(
            left: _offset.dx,
            top: _offset.dy,
            child: Transform.scale(scale: _scale, alignment: Alignment.topLeft, child: widget.child),
          ),
        ],
      ),
    ),
  );
}

/// The zoom, bottom right: − , the percentage (a click: back to 100 %), +.
class ZoomPill extends StatelessWidget {
  const ZoomPill({super.key, required this.canvas, required this.scale});

  final GlobalKey<BoardCanvasState> canvas;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    Widget button(String label, VoidCallback onTap) => HoverBuilder(
      builder: (context, hover) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: hover ? ui.hover : null, borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: uiText(12.5, weight: FontWeight.w600, color: ui.text, tabular: true)),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ui.island,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ui.line),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        button('−', () => canvas.currentState?.zoomBy(1 / 1.25)),
        button('${(scale * 100).round()} %', () => canvas.currentState?.reset()),
        button('+', () => canvas.currentState?.zoomBy(1.25)),
      ]),
    );
  }
}
