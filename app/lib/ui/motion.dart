import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

  /// Selector and tabs thumb: spring 380 / 0.70 (a bit more jelly than
  /// the prototype's 420 / 0.78, asked by the user on 2026-09-29),
  /// stretched by its speed, ≤ 12 px.
  static final thumb = spring(380, .70);
  static const thumbStretch = .015, thumbStretchMax = 12.0;

  /// Small pops (tab icon, answered status): spring 500 / 0.45.
  static final pop = spring(500, .45);

  /// Notification drop: spring 300 / 0.62.
  static final drop = spring(300, .62);

  /// A spring as the prototypes write it: stiffness k, damping ratio z,
  /// unit mass (same as the island's springs).
  static SpringDescription spring(double k, double z) => SpringDescription(mass: 1, stiffness: k, damping: 2 * math.sqrt(k) * z);

  /// Windows asks for fewer animations: fades only, no bounce.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Decorative loops may run: animations allowed, and the widget is shown
  /// (a hidden window is under `TickerMode(enabled: false)`: 0 % CPU).
  static bool loops(BuildContext context) => !reduced(context) && TickerMode.valuesOf(context).enabled;
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
  late final Animation<double> _scale = Tween(
    begin: 1.0,
    end: widget.pressedScale,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut, reverseCurve: Motion.release.flipped));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _on => widget.enabled && widget.onTap != null;

  // The press shows on the raw pointer, at once: a GestureDetector inside
  // something that scrolls waits ~100 ms (tap or drag?) before its
  // onTapDown, which felt like lag. The action still waits for the tap.
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: _on ? SystemMouseCursors.click : MouseCursor.defer,
    child: Listener(
      onPointerDown: _on ? (e) => e.buttons == kPrimaryButton ? _c.forward() : null : null,
      onPointerUp: _on ? (_) => _c.reverse() : null,
      onPointerCancel: _on ? (_) => _c.reverse() : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _on ? widget.onTap : null,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    ),
  );
}

/// Like [Pressable], but soft and a little sticky, like jelly: pressed,
/// it spreads and flattens; let go, it springs back past its shape and
/// wobbles a moment (user request, 2026-09-30).
class JellyPress extends StatefulWidget {
  const JellyPress({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  /// Soft and bouncy: it overshoots and wobbles twice.
  static final spring = Motion.spring(420, .32);

  @override
  State<JellyPress> createState() => _JellyPressState();
}

class _JellyPressState extends State<JellyPress> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
      child: Listener(
        onPointerDown: on ? (e) => e.buttons == kPrimaryButton ? _set(true) : null : null,
        onPointerUp: on ? (_) => _set(false) : null,
        onPointerCancel: on ? (_) => _set(false) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SpringValue(
            target: _down ? 1 : 0,
            spring: JellyPress.spring,
            builder: (context, x, _) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(1 + .1 * x, 1 - .16 * x, 1),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Calls [onDown] as soon as the primary button goes down on [child]: for
/// selectors and tabs, whose thumb must leave at once (no tap-or-drag wait).
class PressDown extends StatelessWidget {
  const PressDown({super.key, required this.child, this.onDown});

  final Widget child;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: onDown == null ? MouseCursor.defer : SystemMouseCursors.click,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onDown == null ? null : (e) => e.buttons == kPrimaryButton ? onDown!() : null,
      child: child,
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

  // Its own layer: only what moves repaints, not the whole window.
  @override
  Widget build(BuildContext context) => widget.builder(context, _c.value, _velocity);
}

/// One clock for every decorative loop (a dot that breathes, the wave, the
/// halo, Mikky in small): 30 frames per second, all in the same frame.
///
/// Why: Flutter redraws the whole window at each frame, whatever moved
/// (measured on the kit: ~6 ms of CPU per frame, 1.4 % of a core with no
/// animation, ~40 % with the loops at 60 fps). Loops at 30 fps halve it
/// and still look smooth; what the user moves (press, thumb, springs)
/// keeps 60 fps. Runs only while someone listens.
abstract final class DecorClock {
  static const fps = 30;
  static final ValueNotifier<Duration> _now = ValueNotifier(Duration.zero);
  static final Stopwatch _watch = Stopwatch();
  static Timer? _timer;
  static int _listeners = 0;

  /// Time since the clock started; changes [fps] times a second.
  static ValueListenable<Duration> get now => _now;

  static void listen(VoidCallback f) {
    _now.addListener(f);
    if (_listeners++ == 0) {
      _watch.start();
      _timer = Timer.periodic(Duration(microseconds: 1000000 ~/ fps), (_) => _now.value = _watch.elapsed);
    }
  }

  static void unlisten(VoidCallback f) {
    _now.removeListener(f);
    if (--_listeners == 0) {
      _timer?.cancel();
      _timer = null;
      _watch.stop();
    }
  }
}
