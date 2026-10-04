import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../theme.dart';
import '../ui/motion.dart';
import '../ui/pixel_fx.dart';
import '../ui/side.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'content/parts.dart';
import 'island_painter.dart';

/// Mikky's state for the agent he stands for: the engine's table
/// ([mikkyStateOf]).
MikkyState mikkyStateFor(AgentStatus? status) => mikkyStateOf(status);

/// Under Mikky on the closed island at the right edge: what the agent he
/// stands for is doing; his name when there is none, nothing to show
/// (paused), or when it needs the user (that goes in the bubble). The
/// name is in Jacquard 24, the pixel font of the name (2026-10-01).
class CompactUnderMikky extends StatelessWidget {
  const CompactUnderMikky({super.key, required this.theme, required this.status});

  final MikkyTheme theme;
  final AgentStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status == null || status!.needsYou ? null : UiStatus.of(status!);
    if (s == null || s == UiStatus.paused) {
      return Text('Mikky', style: sansStyle(theme, size: 17).copyWith(fontFamily: 'Jacquard 24', height: 1));
    }
    return MikkyUiTheme(ui: theme.isLight ? MikkyUi.light : MikkyUi.dark, child: StatusFx(s, size: 18));
  }
}

/// The bubble's state, in it.
class BubbleStatus extends StatelessWidget {
  const BubbleStatus({super.key, required this.theme, required this.status});

  final MikkyTheme theme;
  final AgentStatus status;

  @override
  Widget build(BuildContext context) =>
      MikkyUiTheme(ui: theme.isLight ? MikkyUi.light : MikkyUi.dark, child: StatusFx(UiStatus.of(status), size: 20));
}

/// Where the bubble leaves the closed island at the right edge, from its
/// top left corner: out of the bottom of the tab.
Offset compactBubbleAnchor(Rect island) => Offset(island.center.dx, island.bottom - 20);

/// The closed island at the right edge, for the design boards: the same
/// shape, Mikky in the agent's state, what is under him, and the bubble
/// when the agent needs the user ([detach]: it comes out and goes back,
/// on the island's own spring).
class CompactIslandPreview extends StatelessWidget {
  const CompactIslandPreview({super.key, required this.status, this.program, this.detach = false});

  final AgentStatus? status;

  /// The island shader; null: its plain fallback.
  final ui.FragmentProgram? program;
  final bool detach;

  static const _m = IslandMetrics.right;

  /// Room around it, for its shadow (50 px) and its bubble; glued to the
  /// right.
  static const _left = 60.0, _top = 44.0, _below = 84.0;

  /// The bubble's way out then back (3.2 s), on [SpringSpec.sideBubble].
  static final List<double> _cycle = () {
    final s = Spring(0, SpringSpec.sideBubble)..target = 1;
    final out = <double>[];
    for (var i = 0; i < 384; i++) {
      if (i == 192) s.target = 0;
      s.step(1 / 120);
      out.add(s.value);
    }
    return out;
  }();

  @override
  Widget build(BuildContext context) {
    final needsYou = status?.needsYou ?? false;
    if (!needsYou || !detach) return _at(context, needsYou ? 1 : 0);
    return Looping(
      period: const Duration(milliseconds: 3200),
      frozenAt: .4,
      builder: (context, t) => _at(context, _cycle[(t * _cycle.length).floor().clamp(0, _cycle.length - 1)]),
    );
  }

  Widget _at(BuildContext context, double out) {
    final theme = MikkyUi.of(context).isLight ? MikkyTheme.light : MikkyTheme.dark;
    final w = _m.compact.width, h = _m.compact.height;
    final island = Rect.fromLTWH(_left, _top, w, h);
    final spot = _m.mikkyCompact;
    final bubble = out < .01 ? null : SideBubble.at(compactBubbleAnchor(island), const Offset(0, 1), out);
    // [MiniMikky] draws him at 0.29 of its size, centered at 0.54 down.
    final size = spot.radius / .29;
    return ClipRect(
      child: SizedBox(
        width: island.right,
        height: island.bottom + _below,
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              painter: IslandPainter(
                shader: program?.fragmentShader(),
                shape: Rect.fromLTRB(island.left, island.top, island.right + 40, island.bottom),
                visible: island,
                radius: _m.compactRadius,
                visibility: 1,
                theme: theme,
                devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
                side: bubble,
              ),
            ),
          ),
          Positioned(
            left: island.left + spot.x - size / 2,
            top: island.top + spot.y - size * .54,
            child: MiniMikky(key: ValueKey(status), size: size, state: mikkyStateFor(status)),
          ),
          Positioned(
            left: island.left,
            top: island.top + 57,
            width: w,
            height: 18,
            child: Center(child: CompactUnderMikky(theme: theme, status: status)),
          ),
          if (bubble != null && out > .45)
            Positioned(
              left: bubble.center.dx - 10,
              top: bubble.center.dy - 10,
              width: 20,
              height: 20,
              child: Opacity(opacity: ((out - .45) * 3).clamp(0.0, 1.0), child: BubbleStatus(theme: theme, status: status!)),
            ),
        ]),
      ),
    );
  }
}
