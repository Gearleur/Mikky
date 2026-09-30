import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../overlay/overlay_channel.dart';
import 'icons.dart';
import 'motion.dart';
import 'sliding_hover.dart';
import 'tokens.dart';

/// Our own floating menu, in place of Windows' (user request, 2026-09-30:
/// « notre menu flottant, avec les paramètres et tout »): a light grey
/// panel, the white square of the Oui / Non answers sliding under the item
/// under the mouse, a check for what is on, thin lines between groups. It
/// opens where the mouse was pressed, inside [within] (the small window),
/// and closes on a choice, a click outside or Échap. Null: nothing chosen.
Future<int?> showFloatingMenu(BuildContext within, List<MenuEntry> entries) {
  final overlay = Overlay.maybeOf(within, rootOverlay: true);
  final area = within.findRenderObject() as RenderBox?;
  final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
  if (overlay == null || area == null || overlayBox == null || !area.hasSize) return Future.value(null);
  final ui = MikkyUi.of(within);
  final bounds = MatrixUtils.transformRect(area.getTransformTo(overlayBox), Offset.zero & area.size);
  final at = overlayBox.globalToLocal(FloatingMenu.lastPress ?? area.localToGlobal(area.size.topRight(Offset.zero)));
  final done = Completer<int?>();
  late OverlayEntry entry;
  void close(int? id) {
    if (done.isCompleted) return;
    entry.remove();
    done.complete(id);
  }

  entry = OverlayEntry(
    builder: (context) => MikkyUiTheme(
      ui: ui,
      child: _MenuLayer(bounds: bounds, at: at, entries: entries, onClose: close),
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
}

class _MenuLayer extends StatefulWidget {
  const _MenuLayer({required this.bounds, required this.at, required this.entries, required this.onClose});

  final Rect bounds;
  final Offset at;
  final List<MenuEntry> entries;
  final ValueChanged<int?> onClose;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

class _MenuLayerState extends State<_MenuLayer> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bounds;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose(null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(children: [
        // A click outside: closes, nothing chosen.
        Positioned.fromRect(
          rect: b,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (_) => widget.onClose(null)),
        ),
        Positioned.fromRect(
          rect: b.deflate(8),
          child: CustomSingleChildLayout(
            delegate: _Place(widget.at - b.topLeft - const Offset(8, 8)),
            child: FloatingMenuPanel(entries: widget.entries, onChoose: widget.onClose),
          ),
        ),
      ]),
    );
  }
}

/// Below and to the left of the press, as far as the window allows.
class _Place extends SingleChildLayoutDelegate {
  _Place(this.at);

  final Offset at;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => c.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = at.dx - child.width + 16;
    var y = at.dy + 14;
    if (y + child.height > size.height) y = at.dy - child.height - 14;
    x = x.clamp(0, (size.width - child.width).clamp(0, double.infinity));
    y = y.clamp(0, (size.height - child.height).clamp(0, double.infinity));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_Place old) => old.at != at;
}

/// The menu itself (also shown open on the design boards).
class FloatingMenuPanel extends StatelessWidget {
  const FloatingMenuPanel({super.key, required this.entries, this.onChoose, this.width = 264});

  final List<MenuEntry> entries;
  final ValueChanged<int>? onChoose;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final panel = Container(
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
      child: SlidingHover(
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
      ),
    );
    // Opens with a small spring from its corner.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: Motion.reduced(context) ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Motion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: .96 + .04 * t, alignment: Alignment.topRight, child: child),
      ),
      child: panel,
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
