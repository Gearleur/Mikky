import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../theme.dart';
import '../ui/foundation/motion.dart';
import '../ui/foundation/status.dart';
import '../ui/foundation/tokens.dart';
import '../ui/pixels/pixel_fx.dart';
import '../ui/pixels/status_stack.dart';
import 'content/parts.dart';
import 'island_painter.dart';

// What the closed island shows beside Mikky and in its bubble, at both
// edges: the same widgets in the app and on the « Petite île » board.

/// Mikky's name on the closed islands: Jacquard 24, the pixel font of the
/// name (2026-10-01).
TextStyle compactNameStyle(MikkyTheme theme) =>
    sansStyle(theme, size: 17).copyWith(fontFamily: 'Jacquard 24', height: 1);

/// Under Mikky on the closed island at the right edge: what the agent he
/// stands for is doing; his name when there is none, nothing to show
/// (paused), or when it needs the user (that goes in the bubble).
class CompactUnderMikky extends StatelessWidget {
  const CompactUnderMikky({super.key, required this.theme, required this.status});

  final MikkyTheme theme;
  final AgentStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status == null || status!.needsYou ? null : UiStatus.of(status!);
    if (s == null || s == UiStatus.paused) {
      return Text('Mikky', style: compactNameStyle(theme));
    }
    return MikkyUiTheme(ui: theme.ui, child: StatusFx(s, size: 18));
  }
}

/// Beside Mikky on the closed pill at the top (2026-10-12, user: « les
/// étoiles au milieu… enlève le nom dès qu'il y a une étoile… le numéro,
/// colle-le à droite »): the stars of the agents piled up in the middle
/// ([CompactStars]: blue and up, green alone when it just finished), their
/// number at the right end past three, his name glued to him when there is
/// no star. As big as the closed pill.
class TopPillContent extends StatelessWidget {
  const TopPillContent({super.key, required this.theme, required this.stars});

  final MikkyTheme theme;
  final CompactStars stars;

  static const _m = IslandMetrics.top;

  /// From the right end of the pill to the number.
  static const _endPad = 14.0;

  @override
  Widget build(BuildContext context) {
    final w = _m.compact.width, h = _m.compact.height, spot = _m.mikkyCompact;
    // The stack's own default: [CompactStars.shown] stars.
    final pile = StatusStack.pileWidth(CompactStars.shown);
    return MikkyUiTheme(
      ui: theme.ui,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            Positioned(
              left: spot.x + spot.radius + 5,
              top: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: stars.named ? 1 : 0,
                // Quick: gone as the first star dissolves in.
                duration: Motion.of(context, Motion.hover),
                child: Align(widthFactor: 1, child: Text('Mikky', style: compactNameStyle(theme))),
              ),
            ),
            Positioned(
              left: (w - pile) / 2,
              top: (h - 18) / 2,
              child: StatusStack(stars: [for (final a in stars.stars) (key: a.id, status: UiStatus.of(a.status))]),
            ),
            Positioned(
              right: _endPad,
              top: 0,
              bottom: 0,
              child: Align(widthFactor: 1, child: StackNumber(stars.number)),
            ),
          ],
        ),
      ),
    );
  }
}

/// In the bubble: the « ! » of the alert, orange or red, and how many wait
/// when there are several (one after the other, in order).
class BubbleAlert extends StatelessWidget {
  const BubbleAlert({super.key, required this.theme, required this.status, this.waiting = 1});

  final MikkyTheme theme;
  final AgentStatus status;
  final int waiting;

  @override
  Widget build(BuildContext context) => MikkyUiTheme(
    ui: theme.ui,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // The « ! » is three pixels wide in the middle of its box.
        SizedBox(
          width: 10,
          height: 20,
          child: OverflowBox(maxWidth: 20, child: StatusFx(UiStatus.of(status), size: 20)),
        ),
        if (waiting > 1)
          Padding(
            padding: const EdgeInsets.only(left: 1, top: 1),
            child: Text(
              '$waiting',
              style: uiText(TextSize.badge, color: theme.ui.text2, mono: true, height: 1, weight: FontWeight.w600),
            ),
          ),
      ],
    ),
  );
}

/// Where the bubble leaves the closed island, from its top left corner: out
/// of the middle of its bottom, at both edges (at the top, under the stars:
/// the alert takes their place and drops; 2026-10-12, « elle vient du
/// milieu »). A little lower at the top: once out, it hangs clear of the
/// thin pill.
Offset compactBubbleAnchor(Rect island, IslandEdge edge) =>
    Offset(island.center.dx, island.bottom - (edge == IslandEdge.top ? 16 : 20));

/// What shows in the [bubble] once it is far enough [out], fading in as it
/// drops: [child] on its center.
Widget bubbleContentLayer(SideBubble bubble, double out, {required Widget child}) => Positioned(
  left: bubble.center.dx - 17,
  top: bubble.center.dy - 10,
  width: 34,
  height: 20,
  child: Opacity(opacity: ((out - .3) * 2.4).clamp(0.0, 1.0), child: child),
);
