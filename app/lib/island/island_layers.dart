import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../motion/intro.dart';
import '../theme.dart';
import '../ui/tokens.dart';
import 'compact_view.dart';
import 'content/parts.dart';
import 'island_clip.dart';
import 'island_geometry.dart';
import 'island_painter.dart';

// The layers the island draws over its shape, each one a pure function of
// what the island is at this frame (no state here).

/// Content appears with a fade, a slight blur and a small shift.
class IslandReveal extends StatelessWidget {
  const IslandReveal({super.key, required this.opacity, required this.child});

  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    final blur = (1 - opacity) * 2.5;
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, (1 - opacity) * 6),
        child: blur > .05
            ? ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: child,
              )
            : child,
      ),
    );
  }
}

/// Mikky's greeting (the pop) in the island, its stage the island itself,
/// centered in the greeting's size whatever the island's size while it
/// opens and closes. [t]: seconds into the pop; [fade]: its layer's opacity.
Widget islandGreeting(IslandGeometry geo, MikkyTheme theme, {required double t, required double fade}) {
  final motion = geo.motion;
  final rect = geo.island;
  final size = motion.metrics.greet;
  return Positioned.fromRect(
    rect: rect,
    child: IgnorePointer(
      child: ClipPath(
        clipper: IslandClip(geo.shape.shift(-rect.topLeft), motion.cornerRadius, geo.corners),
        child: OverflowBox(
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: Opacity(
            opacity: fade,
            child: CustomPaint(
              size: Size(size.width, size.height),
              painter: IntroPainter(
                Intros.pop,
                math.max(0, math.min(t, Intros.pop.duration)),
                geo.edge == IslandEdge.top ? 30 : 32,
                stage: false,
                theme: theme,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Right end of the pill: ring, check or number of agents (rule 3).
Widget? pillIndicator(IslandSnapshot s, MikkyTheme theme, {required double now}) {
  final focus = s.focus;
  if (s.agents.isEmpty || focus == null) return null;
  final count = Text('${s.agents.length}', style: monoStyle(theme, size: 11.5));
  if (s.pendingAlerts > 0) return count;
  if (focus.status == AgentStatus.finished) {
    return CustomPaint(
      size: const Size(16, 16),
      painter: PillIndicatorPainter.check(color: theme.status(AgentStatus.finished)),
    );
  }
  final progress = focus.progressAt(now);
  if (progress != null) {
    return CustomPaint(
      size: const Size(16, 16),
      painter: PillIndicatorPainter.ring(progress: progress, color: theme.status(focus.status), track: theme.faint),
    );
  }
  return count;
}

/// What the closed island shows beside Mikky: at the top his name and the
/// indicator; at the right, under him, the state of his agent.
List<Widget> compactLayers(IslandGeometry geo, IslandSnapshot s, MikkyTheme theme, {required double now}) {
  final motion = geo.motion;
  final opacity = motion.compactContentOpacity;
  if (opacity <= 0) return const [];
  final rect = geo.island;
  Widget faded(Widget child) => Opacity(
    opacity: opacity,
    child: Center(child: child),
  );
  switch (geo.edge) {
    case IslandEdge.top:
      final name = Text('Mikky', style: sansStyle(theme));
      final slideUp = math.min(0.0, motion.currentHeight - motion.metrics.compact.height);
      final top = motion.metrics.compact.height / 2 - 9 + slideUp;
      final indicator = pillIndicator(s, theme, now: now);
      return [
        Positioned(left: rect.left + 44, top: top, height: 18, child: faded(name)),
        if (indicator != null)
          Positioned(right: geo.window.width - rect.right + 14, top: top, height: 18, child: faded(indicator)),
      ];
    case IslandEdge.right:
      // Under Mikky, the state of the agent he stands for; his name when
      // there are none, or while the bubble shows it.
      return [
        Positioned(
          left: rect.left,
          top: rect.top + 57,
          width: motion.metrics.compact.width,
          height: 18,
          child: faded(CompactUnderMikky(theme: theme, status: s.bubble ? null : s.focus?.status)),
        ),
      ];
  }
}

/// Thin line that shrinks during the last 10 s before closing (rule 5).
Widget? countdownLayer(IslandGeometry geo, IslandSnapshot s, MikkyTheme theme) {
  final c = s.closeCountdown;
  final motion = geo.motion;
  if (c == null || motion.openContentOpacity <= 0) return null;
  final rect = geo.island;
  final r = motion.cornerRadius;
  final full = rect.width - 2 * r;
  return Positioned(
    left: rect.left + r + full * (1 - c) / 2,
    top: rect.bottom - 5,
    width: full * c,
    height: 2,
    child: DecoratedBox(
      decoration: BoxDecoration(color: theme.secondary, borderRadius: BorderRadius.circular(1)),
    ),
  );
}

/// The small window, cut to the island's current shape while it grows.
/// Shown ([opacity] > 0): drawn and ticking; otherwise kept, not drawn, not
/// ticking (0 % CPU when the island is hidden). [areaKey] marks its content
/// (the floating menus open inside it).
Widget sideWindowLayer(
  IslandGeometry geo,
  MikkyTheme theme, {
  required double opacity,
  required Key areaKey,
  required Widget content,
}) {
  final shown = opacity > 0;
  final motion = geo.motion;
  final rect = geo.island;
  final open = motion.metrics.open(motion.layout);
  final shape = geo.shape.shift(-rect.topLeft);
  return Positioned.fromRect(
    rect: shown ? rect : Rect.fromLTWH(rect.left, rect.top, open.width, open.height),
    child: Offstage(
      offstage: !shown,
      child: TickerMode(
        enabled: shown,
        // Cut to the island's own shape (the shader's continuous corners,
        // flat against the screen's edge): a page over it — the history's
        // dark — fills the island to its corners (2026-10-02).
        child: ClipPath(
          clipper: IslandClip(shape, motion.cornerRadius, geo.corners),
          // The same shape as a rounded rectangle: blurs behind the pages
          // (the field's foot, the history's dark) stay inside it, even
          // while the island grows (2026-10-05).
          child: ClipRRect(
            clipper: IslandRoundClip(shape, motion.cornerRadius),
            child: OverflowBox(
              minWidth: open.width,
              maxWidth: open.width,
              minHeight: open.height,
              maxHeight: open.height,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - opacity) * 6),
                  child: MikkyUiScope(
                    ui: theme.ui,
                    child: KeyedSubtree(key: areaKey, child: content),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
