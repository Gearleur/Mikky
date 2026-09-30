import 'dart:async';

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';
import 'tokens.dart';

/// The hover of a list: the white square of the Oui / Non answers, which
/// slides on a spring to the row under the mouse and rests on the chosen
/// one (user request, 2026-09-30: « le marqueur de placement de la
/// sélection Oui / Non, je l'aime beaucoup »). Rows inside mark
/// themselves with [HoverTarget] — [AgentCard] and [HoverRow] do it on
/// their own when they sit in a [SlidingHover].
class SlidingHover extends StatefulWidget {
  const SlidingHover({super.key, required this.child, this.radius = 10, this.followHover = true, this.hairline = true});

  final Widget child;
  final double radius;

  /// False: the square only shows the chosen row and slides when the
  /// choice changes; the hover is left to the rows (a list where the
  /// square is the indicator, like the boards' sidebar: user request,
  /// 2026-09-30).
  final bool followHover;

  /// A thin line around the square, for a white square on a white
  /// window; none on a grey background, like the Oui / Non picture.
  final bool hairline;

  static SlidingHoverState? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Scope>()?.state;

  @override
  State<SlidingHover> createState() => SlidingHoverState();
}

class SlidingHoverState extends State<SlidingHover> with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController.unbounded(vsync: this)..addListener(_tick);
  final _markerKey = GlobalKey();

  _HoverTargetState? _hover;
  _HoverTargetState? _rest;
  Timer? _leave;

  Rect? _from, _to;
  bool _shown = false;

  _HoverTargetState? get _target => _hover ?? _rest;

  void _tick() => setState(() {});

  Rect? _rectOf(_HoverTargetState t) {
    final box = t.context.findRenderObject() as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    if (box == null || me == null || !box.attached || !me.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: me) & box.size;
  }

  Rect? get _current {
    final from = _from, to = _to;
    if (to == null) return null;
    if (from == null) return to;
    return Rect.lerp(from, to, _move.value);
  }

  void _goTo(_HoverTargetState? t) {
    if (!mounted) return;
    final rect = t == null ? null : _rectOf(t);
    if (rect == null) {
      setState(() => _shown = false);
      return;
    }
    if (!_shown || _to == null || Motion.reduced(context)) {
      // Appears where it is needed, no slide from far away.
      _move.stop();
      setState(() {
        _from = null;
        _to = rect;
        _shown = true;
      });
      return;
    }
    if (rect == _to) return;
    _from = _current;
    _to = rect;
    _shown = true;
    _move.value = 0;
    _move.animateWith(SpringSimulation(Motion.thumb, 0, 1, 0));
  }

  void _enter(_HoverTargetState t) {
    if (!widget.followHover) return;
    _leave?.cancel();
    _hover = t;
    _goTo(t);
  }

  void _exit(_HoverTargetState t) {
    if (_hover != t) return;
    _hover = null;
    // A moment, in case the mouse is only going to the next row.
    _leave?.cancel();
    _leave = Timer(const Duration(milliseconds: 70), () => _goTo(_target));
  }

  void _setRest(_HoverTargetState t, bool rest) {
    if (rest) {
      _rest = t;
    } else if (_rest == t) {
      _rest = null;
    }
    if (_hover == null) _goTo(_target);
  }

  void _gone(_HoverTargetState t) {
    if (_hover == t) _hover = null;
    if (_rest == t) _rest = null;
  }

  @override
  void dispose() {
    _leave?.cancel();
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final rect = _current;
    return _Scope(
      state: this,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (rect != null)
            Positioned.fromRect(
              key: _markerKey,
              rect: rect,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _shown ? 1 : 0,
                  duration: Duration(milliseconds: _shown ? 90 : 160),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ui.thumb,
                      borderRadius: BorderRadius.circular(widget.radius),
                      // A hairline, so the white shows on the white window.
                      border: widget.hairline ? Border.all(color: ui.line, width: .8) : null,
                      boxShadow: [
                        for (final s in ui.shThumb)
                          if (!s.inset) BoxShadow(color: s.color, offset: Offset(s.dx, s.dy), blurRadius: s.blur, spreadRadius: s.spread),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _Scope extends InheritedWidget {
  const _Scope({required this.state, required super.child});

  final SlidingHoverState state;

  @override
  bool updateShouldNotify(_Scope old) => old.state != state;
}

/// A row of a [SlidingHover]: the square comes under it on hover, and
/// rests there while [selected].
class HoverTarget extends StatefulWidget {
  const HoverTarget({super.key, required this.child, this.selected = false});

  final Widget child;
  final bool selected;

  @override
  State<HoverTarget> createState() => _HoverTargetState();
}

class _HoverTargetState extends State<HoverTarget> {
  SlidingHoverState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = SlidingHover.maybeOf(context);
    _markRest();
  }

  @override
  void didUpdateWidget(HoverTarget old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _markRest();
  }

  // After layout: the square needs this row's place.
  void _markRest() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _scope?._setRest(this, widget.selected);
  });

  @override
  void dispose() {
    _scope?._gone(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _scope?._enter(this),
    onExit: (_) => _scope?._exit(this),
    child: widget.child,
  );
}
