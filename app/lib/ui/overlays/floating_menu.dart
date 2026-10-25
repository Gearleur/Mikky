import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../overlay/overlay_channel.dart';
import '../controls/sliding_hover.dart';
import '../foundation/icons.dart';
import '../foundation/motion.dart';
import '../foundation/overlay_area.dart';
import '../foundation/tokens.dart';
import '../pixels/pixel_fx.dart';

/// Our own floating menu, in place of Windows' (user requests, 2026-09-30:
/// « notre menu flottant, avec les paramètres et tout »; « le bouton étoile
/// qui se transforme en menu, smooth, rapide, efficace, un peu gluant »).
/// The grey star stretches into the panel: a soft spring in roomy windows,
/// a brief curve without overshoot in the notch. Items fade in as it opens; on
/// a choice, a click outside or Échap it shrinks back into the button.
/// [from]: the button, in global coordinates (else a round button around
/// the last press). It stays inside [within] (the small window). Null:
/// nothing chosen. A menu opened right after a choice (« Supprimer… »
/// asks again) takes the same panel over, in place (user request,
/// 2026-10-01: « elle doit arriver beaucoup plus vite », not at the
/// bottom).
/// [width]: the panel's; narrower for a few short choices.
/// [anchored]: stays beside the button, opening with a small scale and
/// fade instead of morphing from it. The button stays visible.
Future<int?> showFloatingMenu(
  BuildContext within,
  List<MenuEntry> entries, {
  Rect? from,
  double width = 264,
  bool anchored = false,
}) {
  final done = Completer<int?>();
  if (FloatingMenu._chosen case final panel? when panel.mounted) {
    FloatingMenu._button = null;
    panel._continueWith(entries, done);
    return done.future;
  }
  final found = overlayArea(within);
  if (found == null) return Future.value();
  final (:overlay, :overlayBox, :area, :bounds) = found;
  final ui = MikkyUi.of(within);
  final press = FloatingMenu.lastPress ?? area.localToGlobal(area.size.topRight(const Offset(-30, 30)));
  // Opened by a menu button (its star): the menu grows out of exactly
  // that button and stands in for its star until it is back.
  final pressed = FloatingMenu._button;
  FloatingMenu._button = null;
  final last = FloatingMenu.lastPress;
  final star =
      !anchored &&
      pressed != null &&
      (from == null
          ? last == null || pressed.rect.inflate(2).contains(last)
          : (from.center - pressed.rect.center).distance < 1);
  final button = from ?? (star ? pressed.rect : Rect.fromCircle(center: press, radius: 17));
  final origin = Rect.fromPoints(
    overlayBox.globalToLocal(button.topLeft),
    overlayBox.globalToLocal(button.bottomRight),
  );
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => MikkyUiTheme(
      ui: ui,
      child: _MorphMenu(
        bounds: bounds,
        origin: origin,
        entries: entries,
        star: star,
        width: width,
        anchored: anchored,
        done: done,
        onGone: () {
          entry.remove();
          if (star && identical(FloatingMenu.covering.value, pressed.owner)) FloatingMenu.covering.value = null;
        },
      ),
    ),
  );
  if (star) FloatingMenu.covering.value = pressed.owner;
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

  static ({Rect rect, Object owner})? _button;

  /// A menu folding back after a choice: the next menu takes it over.
  static _MorphMenuState? _chosen;

  static final _open = <_MorphMenuState>{};

  /// Closes every menu at once, nothing chosen: the window they live in is
  /// going away (the island closes).
  static void dismissAll() {
    for (final m in [..._open]) {
      m._dismiss();
    }
  }

  /// A menu button ([owner]) was pressed: the menu it opens grows out of
  /// it. Call before opening the menu.
  static void pressed(BuildContext owner) {
    final box = owner.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _button = (rect: MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size), owner: owner);
  }

  /// The button whose star the open menu draws (it hides its own, so
  /// that only one star shows while the menu opens and folds back).
  static final covering = ValueNotifier<Object?>(null);
}

class _MorphMenu extends StatefulWidget {
  const _MorphMenu({
    required this.bounds,
    required this.origin,
    required this.entries,
    required this.star,
    required this.width,
    required this.anchored,
    required this.done,
    required this.onGone,
  });

  final Rect bounds;
  final Rect origin;
  final List<MenuEntry> entries;

  /// Grows out of a menu button: its star shows at both ends.
  final bool star;
  final double width;
  final bool anchored;

  /// Completed with the choice as soon as it is made.
  final Completer<int?> done;
  final VoidCallback onGone;

  @override
  State<_MorphMenu> createState() => _MorphMenuState();
}

class _MorphMenuState extends State<_MorphMenu> with TickerProviderStateMixin {
  late final _t = AnimationController.unbounded(vsync: this);

  /// From [_from] to [_target] when a follow-up menu takes the panel over
  /// (1: settled).
  late final _swap = AnimationController.unbounded(vsync: this, value: 1);
  final _measure = GlobalKey();
  final _focus = FocusNode();
  late List<MenuEntry> _entries = widget.entries;
  late Completer<int?> _done = widget.done;
  Rect? _target, _from;
  bool _closing = false, _measuring = true;

  bool get _compact => widget.bounds.height < 300;
  double get _margin => _compact ? 12 : 8;
  double get _radius => Radii.xl;
  double get _padding => _compact ? 5 : 6;

  double _panelWidth(BuildContext context) {
    final available = math.min(widget.width, math.max(0.0, widget.bounds.width - 2 * _margin));
    if (!_compact) return available;
    final ui = MikkyUi.of(context);
    final icons = _entries.any((entry) => entry.icon != null);
    final checked = _entries.any((entry) => entry.checked);
    var widest = 0.0;
    for (final entry in _entries.where((entry) => entry.id != 0)) {
      final text = TextPainter(
        text: TextSpan(
          text: entry.label,
          style: uiText(TextSize.label, weight: FontWeight.w500, height: 1.25, color: ui.text),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      widest = math.max(widest, text.width);
      text.dispose();
    }
    final needed = widest + 2 * _padding + 18 + (icons ? 22 : 0) + (checked ? 23 : 0);
    return math.min(available, math.max(200.0, needed.ceilToDouble()));
  }

  /// Bumped when a follow-up menu stops the folding.
  int _run = 0;

  @override
  void initState() {
    super.initState();
    FloatingMenu._open.add(this);
    // First the panel's size, laid out unseen; then it opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = _measure.currentContext?.size;
      if (!mounted || size == null) return;
      setState(() {
        _target = _place(size);
        _measuring = false;
      });
      _focus.requestFocus();
      if (Motion.reduced(context)) {
        _t.value = 1;
      } else if (_compact) {
        _t.animateTo(1, duration: const Duration(milliseconds: 210), curve: Motion.enter);
      } else {
        _t.animateWith(SpringSimulation(FloatingMenu.spring, 0, 1, 0));
      }
    });
  }

  @override
  void dispose() {
    FloatingMenu._open.remove(this);
    if (identical(FloatingMenu._chosen, this)) FloatingMenu._chosen = null;
    if (!_done.isCompleted) _done.complete(null);
    _t.dispose();
    _swap.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A follow-up menu: the panel stops folding, takes its new size where
  /// it is, and shows the new items.
  void _continueWith(List<MenuEntry> entries, Completer<int?> done) {
    FloatingMenu._chosen = null;
    _run++;
    _t.stop();
    _closing = false;
    _done = done;
    setState(() {
      _entries = entries;
      _measuring = true;
      _from = _target;
      _swap.value = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = _measure.currentContext?.size;
      if (!mounted || size == null) return;
      setState(() {
        _from = _target;
        _target = _place(size);
        _measuring = false;
      });
      _focus.requestFocus();
      if (Motion.reduced(context)) {
        _t.value = 1;
        _swap.value = 1;
      } else if (_compact) {
        _t.animateTo(1, duration: const Duration(milliseconds: 210), curve: Motion.enter);
        _swap.animateTo(1, duration: const Duration(milliseconds: 210), curve: Motion.enter);
      } else {
        _t.animateWith(SpringSimulation(FloatingMenu.spring, _t.value, 1, 0));
        _swap.animateWith(SpringSimulation(FloatingMenu.spring, 0, 1, 0));
      }
    });
  }

  /// Down and to the left from the button, its top right corner on the
  /// button's; up when there is no room below; inside the window.
  Rect _place(Size size) {
    final b = widget.bounds.deflate(_margin), o = widget.origin;
    var left = o.right - size.width;
    // Row actions near the edge share the history panel's right margin.
    if (_compact && !widget.anchored && b.right - o.right >= 0 && b.right - o.right <= 32) {
      left = b.right - size.width;
    }
    var top = o.top;
    if (widget.anchored) {
      top = o.bottom + 6;
      if (top + size.height > b.bottom) top = o.top - 6 - size.height;
    } else if (top + size.height > b.bottom) {
      top = o.bottom - size.height;
    }
    left = left.clamp(b.left, math.max(b.left, b.right - size.width));
    top = top.clamp(b.top, math.max(b.top, b.bottom - size.height));
    return Rect.fromLTWH(left, top, size.width, size.height);
  }

  /// Gone at once, nothing chosen.
  void _dismiss() {
    if (!FloatingMenu._open.remove(this)) return;
    _run++;
    _closing = true;
    if (identical(FloatingMenu._chosen, this)) FloatingMenu._chosen = null;
    if (!_done.isCompleted) _done.complete(null);
    widget.onGone();
  }

  Future<void> _close(int? id) async {
    if (_closing) return;
    _closing = true;
    final run = _run;
    // The choice goes at once; a menu it opens takes this panel over.
    if (id != null) FloatingMenu._chosen = this;
    if (!_done.isCompleted) _done.complete(id);
    // Not before the follow-up, if any, had its chance to come.
    await Future<void>.delayed(Duration.zero);
    if (run != _run || !mounted) return;
    if (!Motion.reduced(context)) {
      if (_compact) {
        await _t.animateTo(0, duration: const Duration(milliseconds: 150), curve: Motion.leave);
      } else {
        await _t.animateWith(
          SpringSimulation(
            FloatingMenu.closeSpring,
            _t.value,
            0,
            0,
            tolerance: const Tolerance(distance: .002, velocity: .02),
          ),
        );
      }
      if (run != _run || !mounted) return;
    }
    if (identical(FloatingMenu._chosen, this)) FloatingMenu._chosen = null;
    if (FloatingMenu._open.remove(this)) widget.onGone();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final target = _target;
    final list = SingleChildScrollView(
      primary: false,
      child: _MenuList(entries: _entries, compact: _compact, onChoose: _close),
    );
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          _close(null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          // A click outside: closes, nothing chosen.
          Positioned.fromRect(
            rect: widget.bounds,
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (_) => _close(null)),
          ),
          if (target != null)
            AnimatedBuilder(
              animation: Listenable.merge([_t, _swap]),
              child: RepaintBoundary(child: list),
              builder: (_, content) => _frame(ui, target, content!),
            ),
          if (_measuring)
            Positioned(
              left: 0,
              top: 0,
              child: Offstage(
                child: KeyedSubtree(
                  key: _measure,
                  child: _PanelBox(
                    width: _panelWidth(context),
                    maxHeight: math.max(0, widget.bounds.height - 2 * _margin),
                    compact: _compact,
                    child: SingleChildScrollView(
                      primary: false,
                      child: _MenuList(entries: _entries, compact: _compact),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The button on its way to the panel, at [_t] (0 the button, 1 open).
  Widget _frame(MikkyUi ui, Rect target, Widget list) {
    final t = _t.value;
    final o = widget.origin;
    if (widget.anchored) {
      final shown = _from == null ? target : Rect.lerp(_from, target, _swap.value)!;
      return Positioned.fromRect(
        rect: shown,
        child: IgnorePointer(
          ignoring: t < .8 || _closing,
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: .96 + .04 * t.clamp(0.0, 1.05),
              alignment: target.top < o.top ? Alignment.bottomRight : Alignment.topRight,
              child: _PanelBox(width: target.width, compact: _compact, child: list),
            ),
          ),
        ),
      );
    }
    // Past the button on the way back: the button itself, squeezed a
    // little, before it comes back to its size.
    if (t < 0) {
      if (!widget.star) return const SizedBox.shrink();
      final r = o.deflate(math.min(-t, .2) * o.shortestSide * .8);
      return Positioned.fromRect(
        rect: r,
        child: Center(
          child: Transform.scale(scale: r.width / o.width, child: const PixelStar(PixelFxPalette.grey, size: 14)),
        ),
      );
    }
    // The notch grows as one shape. Roomy menus keep the delayed height.
    final w = t;
    final h = _compact || t >= 1 ? t : math.pow(t.clamp(0.0, 1.0), 1.2).toDouble();
    double lerp(double a, double b, double f) => a + (b - a) * f;
    // It opens upwards when there was no room below.
    final growsUp = target.top < o.top;
    // Taking a follow-up's size, from the panel it was.
    final shown = _from == null ? target : Rect.lerp(_from, target, _swap.value)!;
    final growing = Rect.fromLTRB(
      lerp(o.left, shown.left, w),
      lerp(o.top, shown.top, h),
      lerp(o.right, shown.right, w),
      lerp(o.bottom, shown.bottom, h),
    );
    // A full-height notch menu has no room for the spring's overshoot.
    // Keep every animation frame inside the window, not just its landing.
    final safe = widget.bounds.deflate(_margin).expandToInclude(o);
    final rect = growing.intersect(safe);
    final f = t.clamp(0.0, 1.0);
    final radius = lerp(o.shortestSide / 2, _radius, f);
    final fill = _compact ? Color.lerp(ui.island, ui.well, .4)! : ui.well;
    final color = Color.lerp(fill.withValues(alpha: 0), fill, (f * 1.8).clamp(0.0, 1.0))!;
    // A follow-up's items come in as the panel takes its size.
    final content = _measuring
        ? 0.0
        : math.min(
            // Let the compact frame clear the labels before fading them in.
            // Their icons and first line should not appear half-clipped.
            ((t - (_compact ? .88 : .45)) / (_compact ? .12 : .4)).clamp(0.0, 1.0),
            ((_swap.value - (_compact ? .08 : .3)) / .5).clamp(0.0, 1.0),
          );
    final star = widget.star ? (1 - t / .25).clamp(0.0, 1.0) : 0.0;
    return Positioned.fromRect(
      rect: rect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: ui.line.withValues(alpha: ui.line.a * f)),
          // The shadow appears with the panel; the resting star has none.
          boxShadow: [for (final s in ui.shMenu) s.box.copyWith(color: s.color.withValues(alpha: s.color.a * f))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The grey star fades out and returns as the menu folds back.
              if (star > 0)
                Positioned(
                  left: o.left - rect.left,
                  top: o.top - rect.top,
                  width: o.width,
                  height: o.height,
                  child: Opacity(
                    opacity: star,
                    child: const Center(child: PixelStar(PixelFxPalette.grey, size: 14)),
                  ),
                ),
              // The items, at their final size, uncovered as it opens.
              Positioned(
                right: 0,
                top: growsUp ? null : 0,
                bottom: growsUp ? 0 : null,
                width: target.width,
                height: target.height,
                child: IgnorePointer(
                  ignoring: t < .8 || _swap.value < .8 || _closing,
                  child: Opacity(
                    opacity: content,
                    child: Transform.translate(
                      offset: Offset(0, _compact ? 0 : (1 - content) * -4),
                      child: Padding(padding: EdgeInsets.all(_padding), child: list),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The panel's look, for measuring and for the boards.
class _PanelBox extends StatelessWidget {
  const _PanelBox({required this.child, this.width = 264, this.maxHeight, this.compact = false});

  final Widget child;
  final double width;
  final double? maxHeight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
      padding: EdgeInsets.all(compact ? 4 : 5),
      decoration: BoxDecoration(
        color: compact ? Color.lerp(ui.island, ui.well, .4) : ui.well,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: ui.line),
        boxShadow: [for (final s in ui.shMenu) s.box],
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
  Widget build(BuildContext context) => _PanelBox(
    width: width,
    child: _MenuList(entries: entries, onChoose: onChoose),
  );
}

/// The items, the white square sliding under the one under the mouse.
class _MenuList extends StatelessWidget {
  const _MenuList({required this.entries, this.onChoose, this.compact = false});

  final List<MenuEntry> entries;
  final ValueChanged<int>? onChoose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final hasSelection = entries.any((entry) => entry.checked);
    final hasIcons = compact && entries.any((entry) => entry.icon != null);
    return SlidingHover(
      radius: compact ? Radii.sm : Radii.md,
      color: compact ? ui.hover.withValues(alpha: ui.isLight ? .055 : .09) : null,
      shadows: compact ? const [] : null,
      hairline: false,
      followHover: !hasSelection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in entries)
            if (e.id == 0)
              Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 2 : 4),
                color: ui.line,
              )
            else
              _Item(
                entry: e,
                selectionMenu: hasSelection,
                compact: compact,
                leading: hasIcons,
                onTap: onChoose == null ? null : () => onChoose!(e.id),
              ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.entry,
    required this.selectionMenu,
    required this.compact,
    required this.leading,
    this.onTap,
  });

  final MenuEntry entry;
  final bool selectionMenu;
  final bool compact;
  final bool leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    // What cannot be undone reads in red.
    final danger = entry.label.startsWith('Supprimer') || entry.label.startsWith('Arrêter tous');
    return HoverTarget(
      selected: entry.checked,
      child: HoverBuilder(
        enabled: selectionMenu && !entry.checked,
        builder: (context, hover) => Semantics(
          button: true,
          selected: selectionMenu ? entry.checked : null,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.hover),
                constraints: compact ? const BoxConstraints(minHeight: 26) : null,
                decoration: BoxDecoration(
                  color: hover ? ui.hover : ui.hover.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(compact ? Radii.sm : Radii.md),
                ),
                padding: EdgeInsets.fromLTRB(compact ? 9 : 11, compact ? 4 : 8, compact ? 9 : 10, compact ? 4 : 8),
                child: Row(
                  children: [
                    if (leading) ...[
                      SizedBox.square(
                        dimension: 14,
                        child: entry.icon == null
                            ? null
                            : MikkyIcon(entry.icon!, size: 14, color: danger ? ui.red : ui.text2),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        entry.label,
                        maxLines: compact ? null : 1,
                        overflow: compact ? TextOverflow.visible : TextOverflow.ellipsis,
                        style: uiText(
                          TextSize.label,
                          weight: FontWeight.w500,
                          color: danger ? ui.red : ui.text,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (entry.checked) ...[const SizedBox(width: 8), MikkyIcon('check', size: 15, color: ui.text)],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
