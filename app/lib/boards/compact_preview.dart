import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../island/compact_view.dart';
import '../island/island_painter.dart';
import '../theme.dart';
import '../ui/content/side.dart';
import '../ui/foundation/motion.dart';
import '../ui/foundation/tokens.dart';

/// The island's shader, loaded once for the boards (null: its plain
/// fallback, as when the graphics driver cannot compile it).
final Future<ui.FragmentProgram?> islandProgram = loadIslandProgram();

/// Made-up agents for the closed islands of the board: one per (state,
/// when it began); [justFinished]: the index of the one just finished.
CompactStars fakeStars(List<(AgentStatus, double)> agents, {int? justFinished}) => CompactStars.of([
  for (final (i, (status, at)) in agents.indexed)
    Agent(id: '$i', name: '$i', status: status, startedAt: 0, statusSince: at),
], justFinished: justFinished == null ? null : '$justFinished');

/// The bubble's way out then back (3.2 s), on [SpringSpec.sideBubble]:
/// how far out, frame by frame at 120 a second.
final List<double> _bubbleCycle = () {
  final s = Spring(0, SpringSpec.sideBubble)..target = 1;
  final out = <double>[];
  for (var i = 0; i < 384; i++) {
    if (i == 192) s.target = 0;
    s.step(1 / 120);
    out.add(s.value);
  }
  return out;
}();

/// The closed island at one [edge], for the « Petite île » board: its
/// shape glued to the edge of the frame, Mikky in the state of the agent he
/// stands for ([CompactStars.focus]), what the app shows beside him
/// ([CompactUnderMikky] at the right, [TopPillContent] at the top), and the
/// bubble for what needs the user, with its « ! » ([BubbleAlert]).
/// [detach]: the bubble comes out and goes back, in a loop, on the island's
/// own spring; [out]: how far it is, driven from outside; [answered]: the
/// alert whose bubble goes back in, its « ! » going back with it.
class CompactPreview extends StatelessWidget {
  const CompactPreview(this.edge, this.stars, {super.key, this.detach = false, this.out, this.answered});

  final IslandEdge edge;
  final CompactStars stars;
  final bool detach;
  final double? out;
  final AgentStatus? answered;

  /// Room around it for its shadow (50 px) and its bubble.
  static const _side = 60.0, _below = 90.0;

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.FragmentProgram?>(
    future: islandProgram,
    builder: (context, shot) {
      final alert = stars.alerts.isNotEmpty;
      if (out != null || !alert || !detach) return _at(context, shot.data, out ?? (alert ? 1 : 0));
      return Looping(
        period: const Duration(milliseconds: 3200),
        frozenAt: .4,
        builder: (context, t) =>
            _at(context, shot.data, _bubbleCycle[(t * _bubbleCycle.length).floor().clamp(0, _bubbleCycle.length - 1)]),
      );
    },
  );

  Widget _at(BuildContext context, ui.FragmentProgram? program, double out) {
    final theme = MikkyUi.of(context).isLight ? MikkyTheme.light : MikkyTheme.dark;
    final m = IslandMetrics.of(edge), w = m.compact.width, h = m.compact.height;
    final top = edge == IslandEdge.top;
    // Glued to the top of the frame, or to its right with room above.
    final island = Rect.fromLTWH(_side, top ? 0 : 44, w, h);
    final head = stars.alerts.firstOrNull?.status ?? answered;
    final bubble = out < .01 || head == null
        ? null
        : SideBubble.at(compactBubbleAnchor(island, edge), const Offset(0, 1), out);
    final spot = m.mikkyCompact;
    // [MiniMikky] draws him at 0.29 of its size, centered at 0.54 down.
    final mikky = spot.radius / .29;
    final status = stars.focus?.status;
    return ClipRect(
      child: SizedBox(
        width: island.right + (top ? _side : 0),
        height: island.bottom + _below,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: IslandPainter(
                  shader: program?.fragmentShader(),
                  // Past the edge it is glued to: only the other corners are round.
                  shape: top
                      ? Rect.fromLTRB(island.left, island.top - 40, island.right, island.bottom)
                      : Rect.fromLTRB(island.left, island.top, island.right + 40, island.bottom),
                  visible: island,
                  radius: m.compactRadius,
                  visibility: 1,
                  theme: theme,
                  devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
                  side: bubble,
                ),
              ),
            ),
            Positioned(
              left: island.left + spot.x - mikky / 2,
              top: island.top + spot.y - mikky * .54,
              child: MiniMikky(key: ValueKey(status), size: mikky, state: mikkyStateOf(status)),
            ),
            if (top)
              Positioned.fromRect(
                rect: island,
                child: TopPillContent(theme: theme, stars: stars),
              )
            else
              Positioned(
                left: island.left,
                top: island.top + 57,
                width: w,
                height: 18,
                child: Center(
                  child: CompactUnderMikky(theme: theme, status: stars.alerts.isEmpty ? status : null),
                ),
              ),
            if (bubble != null && out > .3)
              bubbleContentLayer(
                bubble,
                out,
                child: BubbleAlert(theme: theme, status: head!, waiting: stars.alerts.length),
              ),
          ],
        ),
      ),
    );
  }
}
