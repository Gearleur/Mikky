import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
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
  const SideHead({super.key, required this.title, this.leading, this.actions = const [], this.small = false});

  final String title;
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
        child: Row(children: [
          if (leading case final l?) small ? Padding(padding: const EdgeInsets.only(left: 4), child: l) : l,
          SizedBox(width: small ? 14 : 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: uiText(small ? 16 : 20, weight: FontWeight.w600, tracking: -.02, color: ui.text, height: 1.2),
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ]),
      ),
    );
  }
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
        child: Stack(clipBehavior: Clip.none, children: [Positioned(left: -6, top: -6, child: MiniMikky(animate: animate))]),
      );
}

/// Mikky in small (52 px), top left of the home: the real painter, idle,
/// blinking and looking around; still when [animate] is false (goldens)
/// or Windows asks for fewer animations.
class MiniMikky extends StatefulWidget {
  const MiniMikky({super.key, this.size = 52, this.animate = true});

  final double size;
  final bool animate;

  @override
  State<MiniMikky> createState() => _MiniMikkyState();
}

class _MiniMikkyState extends State<MiniMikky> with SingleTickerProviderStateMixin {
  final Mikky _mikky = Mikky(random: math.Random(7));
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 54; i++) {
      _mikky.update(1 / 60, lookX: .2, lookY: .1);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = widget.animate && !Motion.reduced(context);
    if (run && _ticker == null) {
      _ticker = createTicker((t) {
        final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
        _last = t;
        setState(() => _mikky.update(dt));
      })..start();
    } else if (!run) {
      _ticker?.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MikkyUi.of(context).isLight ? MikkyTheme.light : MikkyTheme.dark;
    final s = widget.size;
    return SizedBox.square(
      dimension: s,
      child: CustomPaint(
        painter: MikkyPainter(
          geometry: MikkyGeometry.of(_mikky, s * .29),
          center: Offset(s / 2, s * .54),
          rim: theme.mikkyRim,
          statusColor: theme.status,
          foreground: theme.foreground,
        ),
      ),
    );
  }
}
