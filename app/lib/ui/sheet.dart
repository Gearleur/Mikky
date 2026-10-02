import 'dart:async';
import 'dart:ui' as dui;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'buttons.dart';
import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

/// A page over the window (2026-10-02, the history first): the window
/// behind darkens and blurs a little, and a panel rises from below on a
/// soft spring, about two thirds of the window high (« trop grande »:
/// the home's bar stays in sight above it), its title and a small round ×
/// at the top. A click on the dark, Échap or × closes it: it sinks back,
/// quicker. [within]: the window,
/// below its own Overlay (the home has one), so the sheet stays inside it
/// and its rounded corners. Done when it is closed.
Future<void> showSheet(BuildContext within, {required String title, String? caption, required WidgetBuilder builder}) {
  final overlay = Overlay.maybeOf(within);
  final area = within.findRenderObject() as RenderBox?;
  final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
  if (overlay == null || area == null || overlayBox == null || !area.hasSize) return Future.value();
  final ui = MikkyUi.of(within);
  final bounds = MatrixUtils.transformRect(area.getTransformTo(overlayBox), Offset.zero & area.size);
  final done = Completer<void>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => MikkyUiTheme(
      ui: ui,
      child: _SheetLayer(
        bounds: bounds,
        title: title,
        caption: caption,
        builder: builder,
        onGone: () {
          entry.remove();
          entry.dispose();
          if (!done.isCompleted) done.complete();
        },
      ),
    ),
  );
  overlay.insert(entry);
  return done.future;
}

/// Closes the sheet [context] is in (a row that opens something, say).
abstract final class Sheet {
  static void close(BuildContext context) => context.findAncestorStateOfType<_SheetLayerState>()?._close();
}

/// Opens with a soft spring, ~3 % past; closes quicker, without bounce.
const _openSpring = SpringDescription(mass: 1, stiffness: 260, damping: 25);
const _closeSpring = SpringDescription(mass: 1, stiffness: 420, damping: 42);

class _SheetLayer extends StatefulWidget {
  const _SheetLayer({required this.bounds, required this.title, required this.caption, required this.builder, required this.onGone});

  final Rect bounds;
  final String title;
  final String? caption;
  final WidgetBuilder builder;
  final VoidCallback onGone;

  @override
  State<_SheetLayer> createState() => _SheetLayerState();
}

class _SheetLayerState extends State<_SheetLayer> with SingleTickerProviderStateMixin {
  late final _t = AnimationController.unbounded(vsync: this)..addListener(() => setState(() {}));
  final _focus = FocusNode(debugLabel: 'sheet');
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      if (Motion.reduced(context)) {
        _t.value = 1;
      } else {
        _t.animateWith(SpringSimulation(_openSpring, 0, 1, 0));
      }
    });
  }

  @override
  void dispose() {
    _t.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (!Motion.reduced(context)) {
      await _t.animateWith(SpringSimulation(_closeSpring, _t.value, 0, 0, tolerance: const Tolerance(distance: .003, velocity: .03)));
    }
    if (mounted) widget.onGone();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t.value;
    return Positioned.fromRect(
      rect: widget.bounds,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            _close();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SheetScene(
          t: t,
          onDismiss: _close,
          panel: IgnorePointer(
            ignoring: _closing,
            child: SheetPanel(
              title: widget.title,
              caption: widget.caption,
              onClose: _close,
              child: Builder(builder: widget.builder),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet at [t] (0 gone, 1 open), over a window: the darkened
/// window, and the panel. Also used still, on the boards.
class SheetScene extends StatelessWidget {
  const SheetScene({super.key, required this.t, required this.panel, this.onDismiss});

  final double t;
  final Widget panel;
  final VoidCallback? onDismiss;

  /// The panel's margins from the window's sides and bottom.
  static const side = 14.0;

  /// Its top: a third of the window down, at least below the home's bar.
  static double topOf(double height) => (height * .34).clamp(68.0, double.infinity).roundToDouble();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final shade = t.clamp(0.0, 1.0);
    final dim = (ui.isLight ? .26 : .55) * shade;
    return Stack(
      children: [
        // The window behind: a little blurred, darker; a click there closes.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ClipRect(
              child: BackdropFilter(
                filter: dui.ImageFilter.blur(sigmaX: 1.6 * shade, sigmaY: 1.6 * shade),
                child: CustomPaint(
                  painter: _Backdrop(const Color(0xFF000000).withValues(alpha: dim)),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        // The panel rises from below, a touch small at first.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) => Padding(
              padding: EdgeInsets.fromLTRB(side, topOf(box.maxHeight), side, side),
              child: Opacity(
                opacity: (t * 1.8).clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 48),
                  child: Transform.scale(scale: .96 + .04 * t.clamp(0.0, 1.04), alignment: Alignment.bottomCenter, child: panel),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Backdrop extends CustomPainter {
  _Backdrop(this.dim);

  final Color dim;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(Offset.zero & size, Paint()..color = dim);

  @override
  bool shouldRepaint(_Backdrop old) => old.dim != dim;
}

/// The sheet's panel: the window's color, the floating shadow, a light
/// head (the title, a grey count, a small ×), then [child] (it scrolls by
/// itself).
class SheetPanel extends StatelessWidget {
  const SheetPanel({super.key, required this.title, this.caption, this.onClose, required this.child});

  final String title;

  /// A small grey word after the title (a count).
  final String? caption;
  final VoidCallback? onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Surface(
      color: ui.island,
      radius: Radii.xxl,
      shadows: ui.floating,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: uiText(TextSize.lead, weight: FontWeight.w600, color: ui.text, tracking: -.01, height: 1.2),
                  ),
                  if (caption != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      caption!,
                      style: uiText(TextSize.small, weight: FontWeight.w500, color: ui.text3, tabular: true, height: 1.2),
                    ),
                  ],
                  const Spacer(),
                  RoundButton('x', size: 26, ghost: true, tooltip: 'Fermer', onPressed: onClose),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
