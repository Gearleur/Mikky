import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../overlay/overlay_channel.dart';
import 'icons.dart';
import 'motion.dart';
import 'sliding_hover.dart';
import 'tokens.dart';

/// Our own floating menu, in place of Windows' (user requests, 2026-09-30:
/// « notre menu flottant, avec les paramètres et tout »; « le bouton ···
/// qui se transforme en menu, smooth, rapide, efficace, un peu gluant »).
/// The round button stretches into the panel on a slightly soft spring —
/// wider first, then taller — and the items come in once it is open; on
/// a choice, a click outside or Échap it shrinks back into the button.
/// [from]: the button, in global coordinates (else a round button around
/// the last press). It stays inside [within] (the small window). Null:
/// nothing chosen.
Future<int?> showFloatingMenu(BuildContext within, List<MenuEntry> entries, {Rect? from}) {
  final overlay = Overlay.maybeOf(within);
  final area = within.findRenderObject() as RenderBox?;
  final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
  if (overlay == null || area == null || overlayBox == null || !area.hasSize) return Future.value(null);
  final ui = MikkyUi.of(within);
  final bounds = MatrixUtils.transformRect(area.getTransformTo(overlayBox), Offset.zero & area.size);
  final press = FloatingMenu.lastPress ?? area.localToGlobal(area.size.topRight(const Offset(-30, 30)));
  final button = from ?? Rect.fromCircle(center: press, radius: 17);
  final origin = Rect.fromPoints(overlayBox.globalToLocal(button.topLeft), overlayBox.globalToLocal(button.bottomRight));
  final done = Completer<int?>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => MikkyUiTheme(
      ui: ui,
      child: _MorphMenu(
        bounds: bounds,
        origin: origin,
        entries: entries,
        onGone: (id) {
          entry.remove();
          if (!done.isCompleted) done.complete(id);
        },
      ),
    ),
  );
  overlay.insert(entry);
  return done.future;
}

/// Where menus open: the last press of the mouse, anywhere in the app.
abstract final class FloatingMenu {
  static Offset? lastPress;
  static bool _tracking = false;

  /// Starts following the presses (once).
  static void track() {
    if (_tracking) return;
    _tracking = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event is PointerDownEvent) lastPress = event.position;
    });
  }

  /// Soft, slowing down at the end, one slight bounce (user requests,
  /// 2026-09-30: « un peu trop rapide », then « l'inertie est trop grande,
  /// qu'il ralentisse à la fin et rebondisse légèrement, pas qu'il
  /// s'étire autant »): about 3 % past, open in about 0.25 s.
  static const spring = SpringDescription(mass: 1, stiffness: 300, damping: 26);

  /// Closing: back into the button, which gives a slight gluey bounce —
  /// a touch smaller, then its size (user request, 2026-09-30).
  static const closeSpring = SpringDescription(mass: 1, stiffness: 380, damping: 23);
}

class _MorphMenu extends StatefulWidget {
  const _MorphMenu({required this.bounds, required this.origin, required this.entries, required this.onGone});

  final Rect bounds;
  final Rect origin;
  final List<MenuEntry> entries;
  final ValueChanged<int?> onGone;

  @override
  State<_MorphMenu> createState() => _MorphMenuState();
}

class _MorphMenuState extends State<_MorphMenu> with SingleTickerProviderStateMixin {
  late final _t = AnimationController.unbounded(vsync: this)..addListener(() => setState(() {}));
  final _measure = GlobalKey();
  final _focus = FocusNode();
  Rect? _target;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // First the panel's size, laid out unseen; then it opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = _measure.currentContext?.size;
      if (!mounted || size == null) return;
      setState(() => _target = _place(size));
      _focus.requestFocus();
      if (Motion.reduced(context)) {
        _t.value = 1;
      } else {
        _t.animateWith(SpringSimulation(FloatingMenu.spring, 0, 1, 0));
      }
    });
  }

  @override
  void dispose() {
    _t.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Down and to the left from the button, its top right corner on the
  /// button's; up when there is no room below; inside the window.
  Rect _place(Size size) {
    final b = widget.bounds.deflate(8), o = widget.origin;
    var left = o.right - size.width;
    var top = o.top;
    if (top + size.height > b.bottom) top = o.bottom - size.height;
    left = left.clamp(b.left, math.max(b.left, b.right - size.width));
    top = top.clamp(b.top, math.max(b.top, b.bottom - size.height));
    return Rect.fromLTWH(left, top, size.width, size.height);
  }

  Future<void> _close(int? id) async {
    if (_closing) return;
    _closing = true;
    if (!Motion.reduced(context)) {
      await _t.animateWith(SpringSimulation(FloatingMenu.closeSpring, _t.value, 0, 0, tolerance: const Tolerance(distance: .002, velocity: .02)));
    }
    widget.onGone(id);
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final target = _target;
    final list = _MenuList(entries: widget.entries, onChoose: _close);
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          _close(null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(children: [
        // A click outside: closes, nothing chosen.
        Positioned.fromRect(
          rect: widget.bounds,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (_) => _close(null)),
        ),
        if (target == null)
          Positioned(
            left: 0,
            top: 0,
            child: Offstage(child: KeyedSubtree(key: _measure, child: _PanelBox(child: list))),
          )
        else
          _frame(ui, target, list),
      ]),
    );
  }

  /// The button on its way to the panel, at [_t] (0 the button, 1 open).
  Widget _frame(MikkyUi ui, Rect target, Widget list) {
    final t = _t.value;
    final o = widget.origin;
    // Past the button on the way back: the button itself, squeezed a
    // little, before it comes back to its size.
    if (t < 0) {
      final r = o.deflate(math.min(-t, .2) * o.shortestSide * .8);
      return Positioned.fromRect(
        rect: r,
        child: DecoratedBox(
          decoration: BoxDecoration(color: ui.ctlA, shape: BoxShape.circle),
          child: Center(child: MikkyIcon('more', size: 16, color: ui.text)),
        ),
      );
    }
    // Gluey: the width leads, the height follows a little behind.
    final w = t;
    final h = t < 1 ? math.pow(t.clamp(0.0, 1.0), 1.2).toDouble() : t;
    double lerp(double a, double b, double f) => a + (b - a) * f;
    // It opens upwards when there was no room below.
    final growsUp = target.top < o.top;
    final rect = Rect.fromLTRB(lerp(o.left, target.left, w), lerp(o.top, target.top, h), lerp(o.right, target.right, w), lerp(o.bottom, target.bottom, h));
    final f = t.clamp(0.0, 1.0);
    final radius = lerp(o.shortestSide / 2, 16, f);
    final color = Color.lerp(ui.ctlA, ui.well, (f * 1.8).clamp(0.0, 1.0))!;
    final content = ((t - .45) / .4).clamp(0.0, 1.0);
    final dots = (1 - t / .25).clamp(0.0, 1.0);
    return Positioned.fromRect(
      rect: rect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: ui.line.withValues(alpha: ui.line.a * f)),
          boxShadow: [
            BoxShadow(color: Color.fromRGBO(0, 0, 0, .08 * f), blurRadius: 18, offset: const Offset(0, 6)),
            BoxShadow(color: Color.fromRGBO(0, 0, 0, .05 + .02 * f), blurRadius: 3, offset: const Offset(0, 1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(clipBehavior: Clip.none, children: [
            // The button's three dots, fading as it opens.
            if (dots > 0)
              Positioned(
                right: 0,
                top: growsUp ? null : 0,
                bottom: growsUp ? 0 : null,
                width: o.width,
                height: o.height,
                child: Opacity(opacity: dots, child: Center(child: MikkyIcon('more', size: 16, color: ui.text))),
              ),
            // The items, at their final size, uncovered as it opens.
            Positioned(
              right: 0,
              top: growsUp ? null : 0,
              bottom: growsUp ? 0 : null,
              width: target.width,
              height: target.height,
              child: IgnorePointer(
                ignoring: t < .8 || _closing,
                child: Opacity(
                  opacity: content,
                  child: Transform.translate(
                    offset: Offset(0, (1 - content) * -4),
                    child: Padding(padding: const EdgeInsets.all(5), child: list),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The panel's look, for measuring and for the boards.
class _PanelBox extends StatelessWidget {
  const _PanelBox({required this.child, this.width = 264});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: ui.well,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ui.line),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x0D000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: child,
    );
  }
}

/// The menu, open (shown still on the design boards).
class FloatingMenuPanel extends StatelessWidget {
  const FloatingMenuPanel({super.key, required this.entries, this.onChoose, this.width = 264});

  final List<MenuEntry> entries;
  final ValueChanged<int>? onChoose;
  final double width;

  @override
  Widget build(BuildContext context) => _PanelBox(width: width, child: _MenuList(entries: entries, onChoose: onChoose));
}

/// The items, the white square sliding under the one under the mouse.
class _MenuList extends StatelessWidget {
  const _MenuList({required this.entries, this.onChoose});

  final List<MenuEntry> entries;
  final ValueChanged<int>? onChoose;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SlidingHover(
      radius: 11,
      hairline: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in entries)
            if (e.id == 0)
              Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), color: ui.line)
            else
              _Item(entry: e, onTap: onChoose == null ? null : () => onChoose!(e.id)),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.entry, this.onTap});

  final MenuEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    // What cannot be undone reads in red.
    final danger = entry.label.startsWith('Supprimer') || entry.label.startsWith('Arrêter tous');
    return HoverTarget(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 8, 10, 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(13.5, weight: FontWeight.w500, color: danger ? ui.red : ui.text, height: 1.25),
                ),
              ),
              if (entry.checked) ...[const SizedBox(width: 8), MikkyIcon('check', size: 15, color: ui.text)],
            ]),
          ),
        ),
      ),
    );
  }
}
