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
  final List<Widget> Function(BuildContext context) sections;
}

/// What a frame is (user, 2026-10-05: « qu'on s'y retrouve »), on a tag
/// next to its name.
enum FrameKind {
  /// The app's own screen or component, as it is in the app.
  app('Dans l’app'),

  /// A trial, not in the app (not chosen, or for later).
  trial('Essai'),

  /// A live place to click and play with.
  play('À essayer');

  const FrameKind(this.label);

  final String label;

  Color colorIn(MikkyUi ui) => switch (this) {
    app => ui.green,
    trial => ui.amber,
    play => ui.blue,
  };
}

/// The boards show only the frames of this kind; null: all.
class BoardFilter extends InheritedWidget {
  const BoardFilter({super.key, required this.only, required super.child});

  final FrameKind? only;

  static FrameKind? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BoardFilter>()?.only;

  @override
  bool updateShouldNotify(BoardFilter old) => old.only != only;
}

/// A row of frames on a board, with its title. [kind]: what its frames
/// are, unless a frame says otherwise.
class BoardSection extends StatelessWidget {
  const BoardSection({super.key, required this.title, this.note, required this.frames, this.kind = FrameKind.app});

  final String title;
  final String? note;
  final List<Widget> frames;
  final FrameKind kind;

  FrameKind _kindOf(Widget frame) => frame is BoardFrame ? frame.kind ?? kind : kind;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final only = BoardFilter.of(context);
    final frames = [for (final f in this.frames) if (only == null || _kindOf(f) == only) f];
    if (frames.isEmpty) return const SizedBox.shrink();
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
                child: Text(note!, style: uiText(TextSize.label, color: ui.text2, height: 1.45)),
              ),
            ),
          const SizedBox(height: 22),
          // Every frame's head as tall as the tallest: the screens of a row
          // start on one line (user request, 2026-09-30).
          _HeadHeight(
            height: [for (final f in frames.whereType<BoardFrame>()) f._headHeight(context)].fold(0.0, (a, b) => a > b ? a : b),
            kind: kind,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < frames.length; i++) ...[if (i > 0) const SizedBox(width: 48), frames[i]],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadHeight extends InheritedWidget {
  const _HeadHeight({required this.height, required this.kind, required super.child});

  final double height;

  /// The section's kind, for its frames' tags.
  final FrameKind kind;

  @override
  bool updateShouldNotify(_HeadHeight old) => old.height != height || old.kind != kind;
}

/// One frame on a board: its name and its tag (in the app, a trial, to
/// play with), a line about it, then the thing itself, live (it moves, it
/// can be clicked).
class BoardFrame extends StatelessWidget {
  const BoardFrame({super.key, required this.label, this.note, required this.child, this.width, this.kind});

  final String label;
  final String? note;
  final Widget child;

  /// What it is; null: its section's.
  final FrameKind? kind;

  /// Width of the text above; the child keeps its own size.
  final double? width;

  static TextStyle _labelStyle(MikkyUi ui) => uiText(TextSize.label, weight: FontWeight.w600, color: ui.text2);
  static TextStyle _noteStyle(MikkyUi ui) => uiText(TextSize.caption, color: ui.text3, height: 1.4);

  /// The height of the label and the note, laid out.
  double _headHeight(BuildContext context) {
    final ui = MikkyUi.of(context);
    double measure(String text, TextStyle style, double width) {
      final p = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: width);
      final h = p.height;
      p.dispose();
      return h;
    }

    return measure(label, _labelStyle(ui), double.infinity) + (note == null ? 0 : 3 + measure(note!, _noteStyle(ui), width ?? 320));
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final section = context.dependOnInheritedWidgetOfExactType<_HeadHeight>();
    final k = kind ?? section?.kind ?? FrameKind.app;
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: _labelStyle(ui)),
          const SizedBox(width: 8),
          _Tag(k),
        ]),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: SizedBox(width: width ?? 320, child: Text(note!, style: _noteStyle(ui))),
          ),
      ],
    );
    final height = section?.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (height == null) head else SizedBox(height: height, child: Align(alignment: Alignment.topLeft, child: head)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// A frame's tag: a dot of its color and its kind, small.
class _Tag extends StatelessWidget {
  const _Tag(this.kind);

  final FrameKind kind;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final color = kind.colorIn(ui);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(Radii.sm)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(kind.label, style: uiText(TextSize.badge, weight: FontWeight.w600, color: ui.text2, height: 1.2)),
      ]),
    );
  }
}

/// [child] under an Overlay of its own, as the island's window has one: a
/// page's text can be selected and its menus open inside it.
class OwnOverlay extends StatefulWidget {
  const OwnOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<OwnOverlay> createState() => _OwnOverlayState();
}

class _OwnOverlayState extends State<OwnOverlay> {
  late final _layer = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(OwnOverlay old) {
    super.didUpdateWidget(old);
    _layer.markNeedsBuild();
  }

  @override
  void dispose() {
    _layer.remove();
    _layer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_layer]);
}

/// How a screen behaves, written next to it as in a design spec (user
/// request, 2026-10-01): a title per rule, then what happens.
class BoardRules extends StatelessWidget {
  const BoardRules(this.rules, {super.key, this.width = 520});

  final List<(String, String)> rules;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(color: ui.island, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: ui.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (title, text) in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$title  ', style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text, height: 1.45)),
                TextSpan(text: text, style: uiText(TextSize.small, color: ui.text2, height: 1.45)),
              ])),
            ),
        ],
      ),
    );
  }
}

/// A canvas as in Figma: the wheel scrolls it (Shift: sideways), Ctrl and
/// the wheel zoom around the mouse; dragging moves it — anywhere, even on
/// a frame (a click stays a click), with Space held (the hand), or with
/// the middle button (user request, 2026-09-30). Frames on it stay live.
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

  /// Space held: the hand, every drag moves the canvas.
  bool _hand = false;
  bool _dragging = false;

  double get scale => _scale;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  bool _key(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space || event is KeyRepeatEvent) return false;
    final down = event is KeyDownEvent;
    if (down != _hand) setState(() => _hand = down);
    return false;
  }

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

  void _pan(Offset delta) => setState(() => _offset += delta);

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _signal,
    // The middle button always moves the canvas.
    onPointerDown: (e) {
      if (e.buttons & kMiddleMouseButton != 0) setState(() => _dragging = true);
    },
    onPointerMove: (e) {
      if (e.buttons & kMiddleMouseButton != 0) _pan(e.delta);
    },
    onPointerUp: (_) {
      if (_dragging) setState(() => _dragging = false);
    },
    // A drag anywhere moves it too: past a few pixels the drag wins over
    // the frames' taps; a plain click still reaches them.
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => setState(() => _dragging = true),
      onPanUpdate: (d) => _pan(d.delta),
      onPanEnd: (_) => setState(() => _dragging = false),
      onPanCancel: () => setState(() => _dragging = false),
      child: MouseRegion(
        cursor: _dragging ? SystemMouseCursors.grabbing : (_hand ? SystemMouseCursors.grab : MouseCursor.defer),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: widget.background)),
              Positioned(
                left: _offset.dx,
                top: _offset.dy,
                child: IgnorePointer(
                  // The hand: the frames do not see the mouse.
                  ignoring: _hand || _dragging,
                  child: Transform.scale(scale: _scale, alignment: Alignment.topLeft, child: widget.child),
                ),
              ),
            ],
          ),
        ),
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
            child: Text(label, style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text, tabular: true)),
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
