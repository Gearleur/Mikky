import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// The animations table of `composants.html` (« Les animations »), values
/// as validated.
abstract final class Motion {
  /// `cubic-bezier(.34,1.56,.64,1)`: the release after a press (~5 % over).
  static const release = Cubic(.34, 1.56, .64, 1);

  /// `cubic-bezier(.2,.8,.2,1)`: things that arrive.
  static const enter = Cubic(.2, .8, .2, 1);

  /// `cubic-bezier(.4,0,.2,1)`: things that fold away.
  static const leave = Cubic(.4, 0, .2, 1);

  static const pressDown = Duration(milliseconds: 80);
  static const pressUp = Duration(milliseconds: 340);

  /// Selector and tabs thumb: spring 420 / 0.78, stretched ≤ 10 px.
  static final thumb = spring(420, .78);

  /// Small pops (tab icon, answered status): spring 500 / 0.45.
  static final pop = spring(500, .45);

  /// Notification drop: spring 300 / 0.62.
  static final drop = spring(300, .62);

  /// A spring as the prototypes write it: stiffness k, damping ratio z,
  /// unit mass (same as the island's springs).
  static SpringDescription spring(double k, double z) => SpringDescription(mass: 1, stiffness: k, damping: 2 * math.sqrt(k) * z);

  /// Windows asks for fewer animations: fades only, no bounce.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Shrinks a little while pressed (0.96, round buttons 0.90, in 80 ms),
/// then comes back with a slight bounce (340 ms).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.pressedScale = .96, this.enabled = true});

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.pressDown, reverseDuration: Motion.pressUp);
  late final Animation<double> _scale =
      Tween(begin: 1.0, end: widget.pressedScale).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut, reverseCurve: Motion.release.flipped));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _on => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: _on ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _on ? (_) => _c.forward() : null,
          onTapUp: _on ? (_) => _c.reverse() : null,
          onTapCancel: _on ? () => _c.reverse() : null,
          onTap: _on ? widget.onTap : null,
          child: ScaleTransition(scale: _scale, child: widget.child),
        ),
      );
}

/// A value driven by a spring towards [target], with its speed: the
/// sliding thumb, the jelly island. Rebuilds [builder] while it moves.
class SpringValue extends StatefulWidget {
  const SpringValue({super.key, required this.target, required this.spring, required this.builder});

  final double target;
  final SpringDescription spring;
  final Widget Function(BuildContext context, double value, double velocity) builder;

  @override
  State<SpringValue> createState() => _SpringValueState();
}

class _SpringValueState extends State<SpringValue> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: widget.target)..addListener(() => setState(() {}));
  SpringSimulation? _sim;
  double _t0 = 0;

  @override
  void didUpdateWidget(SpringValue old) {
    super.didUpdateWidget(old);
    if (old.target == widget.target) return;
    if (Motion.reduced(context)) {
      _c.value = widget.target;
      _sim = null;
      return;
    }
    final v = _velocity;
    _sim = SpringSimulation(widget.spring, _c.value, widget.target, v);
    _t0 = 0;
    _c.animateWith(_sim!);
  }

  double get _velocity {
    final sim = _sim;
    if (sim == null || !_c.isAnimating) return 0;
    final t = (_c.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6 - _t0;
    return sim.dx(t);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _c.value, _velocity);
}
