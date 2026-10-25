import 'package:flutter/widgets.dart';

/// Places window sheets above every content layer, including a mascot drawn
/// outside the home's nested Overlay. Only the sheets take the window's clip;
/// its shadows and detached bubbles can still extend beyond that shape.
class SheetHost extends StatefulWidget {
  const SheetHost({super.key, required this.child, this.clipper, this.roundClipper, this.enabled = true});

  final Widget child;
  final CustomClipper<Path>? clipper;
  final CustomClipper<RRect>? roundClipper;
  final bool enabled;

  static OverlayState? overlayOf(BuildContext context) =>
      context.findAncestorStateOfType<_SheetHostState>()?._overlay.currentState;

  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SheetHostClip>()?.enabled ?? true;

  static Widget clip(BuildContext context, {required Widget child}) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SheetHostClip>();
    if (scope?.roundClipper != null) child = ClipRRect(clipper: scope!.roundClipper, child: child);
    if (scope?.clipper != null) child = ClipPath(clipper: scope!.clipper, child: child);
    return Offstage(
      offstage: !(scope?.enabled ?? true),
      child: TickerMode(enabled: scope?.enabled ?? true, child: child),
    );
  }

  @override
  State<SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<SheetHost> {
  final _overlay = GlobalKey<OverlayState>();
  late final _content = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(SheetHost old) {
    super.didUpdateWidget(old);
    if (old.child != widget.child) _content.markNeedsBuild();
  }

  @override
  void dispose() {
    _content.remove();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SheetHostClip(
    clipper: widget.clipper,
    roundClipper: widget.roundClipper,
    enabled: widget.enabled,
    child: Overlay(key: _overlay, initialEntries: [_content]),
  );
}

class _SheetHostClip extends InheritedWidget {
  const _SheetHostClip({
    required this.clipper,
    required this.roundClipper,
    required this.enabled,
    required super.child,
  });

  final CustomClipper<Path>? clipper;
  final CustomClipper<RRect>? roundClipper;
  final bool enabled;

  @override
  bool updateShouldNotify(_SheetHostClip old) =>
      enabled != old.enabled || _reclip(clipper, old.clipper) || _reclip(roundClipper, old.roundClipper);

  bool _reclip<T>(CustomClipper<T>? next, CustomClipper<T>? old) =>
      next != old && (next == null || old == null || next.runtimeType != old.runtimeType || next.shouldReclip(old));
}
