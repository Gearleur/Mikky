import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'compact_view.dart';
import 'island_painter.dart';

/// Size of the transparent window for each edge: big enough for the open
/// island, the bubble and the shadow, so it never resizes while animating.
Size windowSizeFor(IslandEdge edge) => switch (edge) {
  // At the top, the notch is 700 wide (2026-10-05), up to 380 high
  // for an agent's page: room for their shadow.
  IslandEdge.top => const Size(840, 480),
  // At the right, up to 344 × 520 (an agent's page): room for its
  // shadow on the left.
  IslandEdge.right => const Size(420, 700),
};

/// Where the island and its parts are in the window, at this frame: read
/// from its [motion] and from how far its split [bubble] is out.
class IslandGeometry {
  const IslandGeometry(this.motion, this.bubble);

  final IslandMotion motion;

  /// The split bubble's spring value (0: in, 1: out).
  final double bubble;

  /// The shader box goes this far past the screen edge: only the corners
  /// away from the edge are rounded.
  static const pastEdge = 40.0;

  IslandEdge get edge => motion.edge;
  Size get window => windowSizeFor(edge);

  /// The part of the island on screen, in window coordinates.
  Rect get island {
    final w = motion.currentWidth, h = motion.currentHeight, win = window;
    return switch (edge) {
      IslandEdge.top => Rect.fromLTWH(win.width / 2 - w / 2, 0, w, h),
      IslandEdge.right => Rect.fromLTWH(win.width - w, win.height / 2 - h / 2, w, h),
    };
  }

  /// The island's corners: continuous while closed (the pill), round once
  /// open, like the boards (user, 2026-10-02: « les bords des planches
  /// sont mieux »), sliding from one to the other as it opens.
  double get corners => 4 - 2 * motion.openness.clamp(0.0, 1.0);

  /// The shader's box: the island, past the screen edge.
  Rect get shape {
    final r = island;
    return switch (edge) {
      IslandEdge.top => Rect.fromLTRB(r.left, -pastEdge, r.right, r.bottom),
      IslandEdge.right => Rect.fromLTRB(r.left, r.top, r.right + pastEdge, r.bottom),
    };
  }

  /// Bumping the cursor into the edge, near the island, brings it out.
  Rect get hotZone {
    final win = window;
    return switch (edge) {
      IslandEdge.top => Rect.fromLTRB(win.width / 2 - 120, -1, win.width / 2 + 120, 10),
      IslandEdge.right => Rect.fromLTRB(win.width - 10, win.height / 2 - 150, win.width + 1, win.height / 2 + 150),
    };
  }

  Offset get mikkyCenter => island.topLeft + Offset(motion.mikkyX, motion.mikkyY);

  /// [point] is on Mikky (a little wider than his body).
  bool onMikky(Offset point) => (point - mikkyCenter).distance < motion.mikkyRadius * 1.3;

  /// How far the split bubble is out: only while the island is closed.
  double get bubbleOut => bubble.clamp(0.0, 1.2) * (1 - (motion.openness * 2).clamp(0.0, 1.0));

  /// Top: out of the right end of the pill. Right: out of the bottom of the tab.
  SideBubble? get sideBubble {
    final out = bubbleOut;
    if (out < .01 || motion.visibility <= 0) return null;
    final r = island;
    return switch (edge) {
      IslandEdge.top => SideBubble.at(Offset(r.right - 20, motion.metrics.compact.height / 2), const Offset(1, 0), out),
      IslandEdge.right => SideBubble.at(compactBubbleAnchor(r), const Offset(0, 1), out),
    };
  }

  /// Where clicks land on the island (with its bubble), the rest of the
  /// window letting them through.
  Rect get hit {
    if (motion.visibility <= 0) return Rect.zero;
    final side = sideBubble;
    final r = island;
    return side == null ? r : r.expandToInclude(Rect.fromCircle(center: side.center, radius: side.radius));
  }
}
