import 'dart:async';
import 'dart:ui' as dui;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../controls/buttons.dart';
import '../foundation/motion.dart';
import '../foundation/overlay_area.dart';
import '../foundation/surface.dart';
import '../foundation/tokens.dart';
import 'sheet_host.dart';

/// A page over the window (2026-10-02, the history first): the window
/// behind darkens and blurs a little, and a panel comes up in its middle
/// on a soft spring — at most 316 wide, two thirds of a tall window, all
/// but its margins in a low one (the top home) — its title and a small
/// round × at the top. A click on the dark, Échap or × closes it: it
/// sinks back, quicker. [within] supplies the window's bounds. A [SheetHost]
/// puts the sheet above all its layers and keeps the island's rounded clip;
/// without a host, it uses the nearest Overlay. Done when it is closed.
Future<void> showSheet(BuildContext within, {required String title, String? caption, required WidgetBuilder builder}) =>
    _showSheet(
      within,
      builder: (context) => SheetPanel(
        title: title,
        caption: caption,
        onClose: () => Sheet.close(context),
        child: Builder(builder: builder),
      ),
    );

/// The same sheet motion, backdrop and keyboard behavior for a page whose
/// controls sit outside its panel, such as the top history trial.
Future<void> showSheetPage(
  BuildContext within, {
  required WidgetBuilder builder,
  bool fill = true,
  Listenable? themeUpdates,
  MikkyUi Function(BuildContext)? resolveTheme,
}) => _showSheet(within, builder: builder, fill: fill, themeUpdates: themeUpdates, resolveTheme: resolveTheme);

Future<void> _showSheet(
  BuildContext within, {
  required WidgetBuilder builder,
  bool fill = false,
  Listenable? themeUpdates,
  MikkyUi Function(BuildContext)? resolveTheme,
}) {
  if (!SheetHost.enabledOf(within)) return Future.value();
  final found = overlayArea(within, overlay: SheetHost.overlayOf(within));
  if (found == null) return Future.value();
  final (:overlay, :bounds, overlayBox: _, area: _) = found;
  final ui = MikkyUi.of(within);
  final done = Completer<void>();
  late OverlayEntry entry;
  Widget layer(BuildContext context) => Positioned.fill(
    child: SheetHost.clip(
      context,
      child: Stack(
        children: [
          MikkyUiTheme(
            ui: resolveTheme?.call(context) ?? ui,
            child: _SheetLayer(
              bounds: bounds,
              builder: builder,
              fill: fill,
              onDisposed: () {
                if (!done.isCompleted) done.complete();
              },
              onGone: () {
                entry.remove();
                entry.dispose();
                if (!done.isCompleted) done.complete();
              },
            ),
          ),
        ],
      ),
    ),
  );
  entry = OverlayEntry(
    builder: (context) => themeUpdates == null
        ? layer(context)
        : ListenableBuilder(listenable: themeUpdates, builder: (context, _) => layer(context)),
  );
  overlay.insert(entry);
  return done.future;
}

/// Closes the sheet [context] is in (a row that opens something, say).
abstract final class Sheet {
  static void close(BuildContext context, {bool animated = true}) => unawaited(dismiss(context, animated: animated));

  static Future<void> dismiss(BuildContext context, {bool animated = true}) =>
      context.findAncestorStateOfType<_SheetLayerState>()?._close(animated: animated) ?? Future.value();
}

/// Opens with a soft spring, ~3 % past; closes quicker, without bounce.
const _openSpring = SpringDescription(mass: 1, stiffness: 260, damping: 25);
const _closeSpring = SpringDescription(mass: 1, stiffness: 420, damping: 42);

// The page arrives at the island's own pace; its detached controls follow
// the slower split-bubble spring rather than the page's scale.
final _pageOpenSpring = Motion.spring(SpringSpec.island.stiffness, SpringSpec.island.dampingRatio);
// Keep the liquid separation, with a quicker travel and a quiet landing.
const _pageDetachPace = 1.5, _pageDetachDamping = .88;
SpringDescription get _pageDetachSpring =>
    Motion.spring(SpringSpec.sideBubble.stiffness * _pageDetachPace * _pageDetachPace, _pageDetachDamping);
final _pageRejoinSpring = Motion.spring(SpringSpec.sideBubble.stiffness * 4, SpringSpec.sideBubble.dampingRatio);
final _pageCloseSpring = Motion.spring(900, .95);

/// Entrance progress for content that shares the sheet's motion clock.
/// A static preview outside a sheet is already at rest.
class SheetMotion extends InheritedWidget {
  const SheetMotion({super.key, required this.progress, this.detachment = 1, required super.child});

  final double progress;
  final double detachment;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SheetMotion>()?.progress ?? 1;
  static double detachmentOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SheetMotion>()?.detachment ?? 1;

  @override
  bool updateShouldNotify(SheetMotion old) => old.progress != progress || old.detachment != detachment;
}

class _SheetLayer extends StatefulWidget {
  const _SheetLayer({
    required this.bounds,
    required this.builder,
    required this.fill,
    required this.onGone,
    required this.onDisposed,
  });

  final Rect bounds;
  final WidgetBuilder builder;
  final bool fill;
  final VoidCallback onGone;
  final VoidCallback onDisposed;

  @override
  State<_SheetLayer> createState() => _SheetLayerState();
}

class _SheetLayerState extends State<_SheetLayer> with TickerProviderStateMixin {
  late final _t = AnimationController.unbounded(vsync: this)..addListener(() => setState(() {}));
  late final _detach = AnimationController.unbounded(vsync: this)..addListener(() => setState(() {}));
  final _focus = FocusScopeNode(debugLabel: 'sheet');
  bool _closing = false;
  bool _gone = false;
  late final Widget _body = Builder(builder: (context) => widget.builder(context));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      if (Motion.reduced(context)) {
        _t.value = 1;
        _detach.value = 1;
      } else {
        _t.animateWith(SpringSimulation(widget.fill ? _pageOpenSpring : _openSpring, 0, 1, 0));
        if (widget.fill) _detach.animateWith(SpringSimulation(_pageDetachSpring, 0, 1, 0));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A sheet in the island's outer Overlay must not outlive its window
    // or keep its activity stars ticking while that window is hidden.
    if (!SheetHost.enabledOf(context)) WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
  }

  void _finish() {
    if (!mounted || _gone) return;
    _gone = true;
    widget.onGone();
  }

  @override
  void dispose() {
    _t.dispose();
    _detach.dispose();
    _focus.dispose();
    widget.onDisposed();
    super.dispose();
  }

  Future<void> _close({bool animated = true}) async {
    if (_closing) return;
    _closing = true;
    if (animated && !Motion.reduced(context)) {
      if (widget.fill) {
        _detach.animateWith(SpringSimulation(_pageRejoinSpring, _detach.value, 0, _detach.velocity));
      }
      try {
        await _t
            .animateWith(
              SpringSimulation(
                widget.fill ? _pageCloseSpring : _closeSpring,
                _t.value,
                0,
                0,
                tolerance: widget.fill
                    ? const Tolerance(distance: .008, velocity: .2)
                    : const Tolerance(distance: .003, velocity: .03),
              ),
            )
            .orCancel;
      } on TickerCanceled {
        return;
      }
    }
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t.value;
    return Positioned.fromRect(
      rect: widget.bounds,
      child: FocusScope(
        node: _focus,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            _close();
            return KeyEventResult.handled;
          }
          // Content receives keys first. Unused arrows stop here instead
          // of turning the home's pages behind a modal; Tab stays in its scope.
          if (e is KeyDownEvent &&
              (e.logicalKey == LogicalKeyboardKey.arrowLeft || e.logicalKey == LogicalKeyboardKey.arrowRight)) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SheetScene(
          t: t,
          fill: widget.fill,
          onDismiss: _close,
          panel: SheetMotion(
            progress: t,
            detachment: widget.fill ? _detach.value : 1,
            child: IgnorePointer(ignoring: _closing, child: _body),
          ),
        ),
      ),
    );
  }
}

/// The sheet at [t] (0 gone, 1 open), over a window: the darkened
/// window, and the panel. Also used still, on the boards.
class SheetScene extends StatelessWidget {
  const SheetScene({super.key, required this.t, required this.panel, this.onDismiss, this.fill = false});

  final double t;
  final Widget panel;
  final VoidCallback? onDismiss;

  /// A page with detached controls can use the whole window over the
  /// same translucent, blurred backdrop as the centered sheet.
  final bool fill;

  /// The panel's smallest margin from the window's edges, its widest.
  static const margin = 14.0, maxWidth = 316.0;

  /// The panel's size in a window of [size]: centered, recentered by the
  /// user (2026-10-02); two thirds of a tall window, nearly all of a low
  /// one.
  static Size panelFor(Size size) => Size(
    (size.width - 2 * margin).clamp(0.0, maxWidth),
    (size.height >= 400 ? size.height * .68 : size.height - 2 * margin).roundToDouble(),
  );

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
        // The panel comes up into the middle, a touch small at first.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) => Center(
              child: SizedBox.fromSize(
                size: fill ? box.biggest : panelFor(box.biggest),
                child: Opacity(
                  opacity: (fill ? shade : t * 1.8).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * (fill ? 8 : 28)),
                    child: fill
                        ? Transform.scale(
                            scaleX: .98 + .02 * t.clamp(0.0, 1.04),
                            scaleY: .95 + .05 * t.clamp(0.0, 1.04),
                            child: panel,
                          )
                        : Transform.scale(scale: .95 + .05 * t.clamp(0.0, 1.04), child: panel),
                  ),
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
                children: [
                  Text(
                    title,
                    style: uiText(TextSize.lead, weight: FontWeight.w600, color: ui.text, tracking: -.01, height: 1.2),
                  ),
                  if (caption != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      caption!,
                      style: uiText(
                        TextSize.small,
                        weight: FontWeight.w500,
                        color: ui.text3,
                        tabular: true,
                        height: 1.2,
                      ),
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
