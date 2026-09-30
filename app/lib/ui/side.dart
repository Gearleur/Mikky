import 'dart:math' as math;
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

/// `.side`: the small window at the right edge, 320 × 560, radius 38, the
/// island's color and shadow.
class SideFrame extends StatelessWidget {
  const SideFrame({super.key, required this.child, this.width = 320, this.height = 560});

  final Widget child;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Surface(
      width: width,
      height: height,
      radius: 38,
      color: ui.island,
      shadows: ui.islandShadow,
      child: ClipRRect(borderRadius: BorderRadius.circular(38), child: child),
    );
  }
}

/// `.side-head`: 68 px — Mikky small (or a back button), the title, and
/// round buttons on the right.
class SideHead extends StatelessWidget {
  const SideHead({super.key, this.title, this.leading, this.actions = const [], this.small = false, this.titleMark});

  /// A small sign right after the title (the violet star of « Relance
  /// automatique » after « Agents »).
  final Widget? titleMark;

  /// None on an agent's page: its buttons float over the thread (user
  /// request, 2026-09-30).
  final String? title;
  final Widget? leading;
  final List<Widget> actions;

  /// A page title (16 px, next to a back button) instead of « Agents ».
  final bool small;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 16, 6),
        child: Row(
          children: [
            if (leading case final l?) small ? Padding(padding: const EdgeInsets.only(left: 4), child: l) : l,
            SizedBox(width: small ? 14 : 8),
            Expanded(
              child: title == null
                  ? const SizedBox.shrink()
                  : Row(children: [
                      Flexible(
                        child: Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: uiText(small ? 16 : 20, weight: FontWeight.w600, tracking: -.02, color: ui.text, height: 1.2),
                        ),
                      ),
                      ?titleMark,
                    ]),
            ),
            for (final a in actions) ...[const SizedBox(width: 8), a],
          ],
        ),
      ),
    );
  }
}

/// A soft blur on the edge of a page, stronger at the edge, gone
/// further in, with a veil of the window's color: the thread passes under
/// the floating buttons at the top and under the field at the bottom
/// (user request, 2026-09-30: « ultra smooth, ultra moderne »). Layers of
/// light blur stack up towards the edge; their lengths are set so the
/// blur grows evenly from nothing (layer i reaches 1 − √(i/n) of the
/// way), not strong from its first pixels. Still: costs nothing when
/// nothing moves.
class EdgeBlur extends StatelessWidget {
  const EdgeBlur({super.key, required this.top, this.height = 76, this.layers = 12, this.sigma = 1.25, this.veil = .8, this.ramp = .5});

  /// How the blur grows towards the edge: layer i reaches 1 − (i/n)^ramp
  /// of the way; .5 grows evenly, lower is strong sooner, higher later.
  final double ramp;

  /// The top edge (else the bottom).
  final bool top;
  final double height;
  final int layers;

  /// Blur of each layer; they add up towards the edge.
  final double sigma;

  /// Opacity of the window's color at the edge.
  final double veil;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    // How far layer i reaches from the edge.
    double reach(int i) => height * (1 - math.pow(i / layers, ramp).toDouble());
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            for (var i = 0; i < layers; i++)
              Positioned(
                // Off the window's sides: the blur would take in its edge.
                left: 8,
                right: 8,
                top: top ? 0 : height - reach(i),
                bottom: top ? height - reach(i) : 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                    end: top ? Alignment.bottomCenter : Alignment.topCenter,
                    // Eased: fades in slowly from the thread's side.
                    colors: [
                      for (final k in [1.0, .72, .45, .22, .07, 0.0]) ui.island.withValues(alpha: veil * k),
                    ],
                    stops: const [0, .2, .4, .6, .8, 1],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The top blur of an agent's page, with the values the user set with
/// sliders in the design boards (2026-09-30).
class TopBlur extends StatelessWidget {
  const TopBlur({super.key});

  @override
  Widget build(BuildContext context) => const EdgeBlur(top: true, height: 65, layers: 3, sigma: .9, veil: .38, ramp: 1.05);
}

/// The home's leading Mikky: 52 px drawn with the prototype's negative
/// margins (`-6px -4px -6px -6px`), so it takes 42 × 40 in the head.
class HeadMikky extends StatelessWidget {
  const HeadMikky({super.key, this.animate = true});

  final bool animate;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    height: 40,
    child: Stack(
      clipBehavior: Clip.none,
      children: [Positioned(left: -6, top: -6, child: MiniMikky(animate: animate))],
    ),
  );
}

/// Mikky in small (52 px), top left of the home: the real painter, idle,
/// blinking and looking around; still when [animate] is false (goldens)
/// or Windows asks for fewer animations.
class MiniMikky extends StatefulWidget {
  const MiniMikky({super.key, this.size = 52, this.animate = true, this.state = MikkyState.idle, this.badge = true});

  final double size;
  final bool animate;

  /// His state (the boards show each one).
  final MikkyState state;

  /// The state's badge next to him (off in the logo).
  final bool badge;

  @override
  State<MiniMikky> createState() => _MiniMikkyState();
}

class _MiniMikkyState extends State<MiniMikky> {
  final Mikky _mikky = Mikky(random: math.Random(7));
  bool _onClock = false;
  Duration? _last;

  @override
  void initState() {
    super.initState();
    _mikky.setState(widget.state);
    for (var i = 0; i < 54; i++) {
      _mikky.update(1 / 60, lookX: .2, lookY: .1);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // On the DecorClock (30 fps), like every loop of the window.
    final run = widget.animate && Motion.loops(context);
    if (run && !_onClock) {
      DecorClock.listen(_tick);
      _onClock = true;
    } else if (!run && _onClock) {
      DecorClock.unlisten(_tick);
      _onClock = false;
    }
  }

  void _tick() {
    final now = DecorClock.now.value;
    final dt = _last == null ? 0.0 : ((now - _last!).inMicroseconds / 1e6).clamp(0.0, .1);
    _last = now;
    setState(() => _mikky.update(dt));
  }

  @override
  void dispose() {
    if (_onClock) DecorClock.unlisten(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MikkyUi.of(context).isLight ? MikkyTheme.light : MikkyTheme.dark;
    final s = widget.size;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: s,
        child: CustomPaint(
          painter: MikkyPainter(
            geometry: MikkyGeometry.of(_mikky, s * .29),
            center: Offset(s / 2, s * .54),
            rim: theme.mikkyRim,
            statusColor: theme.status,
            foreground: theme.foreground,
            showBadge: widget.badge,
          ),
        ),
      ),
    );
  }
}
