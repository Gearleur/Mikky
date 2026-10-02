import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
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

  /// A light grey coming under the mouse, a small sign showing up.
  static const hover = Duration(milliseconds: 140);

  /// A text changing color.
  static const fade = Duration(milliseconds: 180);

  /// Something that opens or folds, a chevron that turns.
  static const fold = Duration(milliseconds: 300);

  /// Something that slides: a page coming in, a switch's knob.
  static const slide = Duration(milliseconds: 380);

  /// [d], or at once when Windows asks for fewer animations.
  static Duration of(BuildContext context, Duration d) => reduced(context) ? const Duration(milliseconds: 1) : d;

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

/// Builds [builder] with whether the mouse is over it (user request,
/// 2026-09-30: everything that can be clicked answers the mouse).
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({super.key, required this.builder, this.enabled = true});

  final Widget Function(BuildContext context, bool hover) builder;
  final bool enabled;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder(context, false);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.builder(context, _hover),
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

/// A widget animated forever by one controller of [period]; stops (and
/// shows [frozenAt]) when Windows asks for fewer animations. [frozenAt]
/// is where the CSS animation ends, as the prototypes show with
/// `prefers-reduced-motion` (and their `#calme` captures).
class Looping extends StatefulWidget {
  const Looping({super.key, required this.period, required this.builder, this.frozenAt = 0, this.repeat = true});

  final Duration period;
  final Widget Function(BuildContext context, double t) builder;
  final double frozenAt;

  /// False: plays once (a pop, a shake).
  final bool repeat;

  @override
  State<Looping> createState() => _LoopingState();
}

class _LoopingState extends State<Looping> with SingleTickerProviderStateMixin {
  // One-shot (pop, shake): short, at 60 fps. Loops: on the DecorClock.
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);
  bool _onClock = false;
  Duration? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = Motion.reduced(context);
    if (!widget.repeat) {
      if (reduced) {
        _c.value = 1;
      } else if (_c.value == 0 && !_c.isAnimating) {
        _c.forward();
      }
      return;
    }
    final run = Motion.loops(context);
    if (!run && _onClock) {
      DecorClock.unlisten(_tick);
      _onClock = false;
    } else if (run && !_onClock) {
      DecorClock.listen(_tick);
      _onClock = true;
    }
  }

  void _tick() => setState(() {});

  double get _t {
    if (!_onClock) return widget.frozenAt;
    final now = DecorClock.now.value;
    final start = _start ??= now;
    final period = widget.period.inMicroseconds;
    return ((now - start).inMicroseconds % period) / period;
  }

  @override
  void dispose() {
    if (_onClock) DecorClock.unlisten(_tick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: widget.repeat ? widget.builder(context, _t) : AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, _c.value)),
  );
}

/// Whether the last thing the user did was on the keyboard: a focus ring
/// shows only then (2026-10-02). Flutter's own highlight mode counts the
/// mouse as « traditional » on Windows, so a ring stayed after a click.
abstract final class KeyboardUse {
  static bool _last = false;
  static bool _tracking = false;

  /// The last input was a key (not a press of the mouse or a finger).
  static bool get last {
    _track();
    return _last;
  }

  /// Starts following the input (once); call before the first key counts.
  static void start() => _track();

  static void _track() {
    if (_tracking) return;
    _tracking = true;
    HardwareKeyboard.instance.addHandler((event) {
      if (event is KeyDownEvent) _last = true;
      return false;
    });
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event is PointerDownEvent) _last = false;
    });
  }
}
