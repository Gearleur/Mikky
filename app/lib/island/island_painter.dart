import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../theme.dart';

/// Loads the island shader once. Null if it does not compile (graphics
/// driver): the island is then drawn with a plain rounded rectangle.
Future<ui.FragmentProgram?> loadIslandProgram() async {
  try {
    return await ui.FragmentProgram.fromAsset('shaders/island.frag');
  } catch (e) {
    debugPrint('mikky: island shader unavailable, plain fallback ($e)');
    return null;
  }
}

/// The island's shape.
///
/// [shape] is the box given to the shader: the visible island extended past
/// the screen edge it is glued to, so only the corners away from that edge
/// are rounded. [visible] is the part on screen.
class IslandPainter extends CustomPainter {
  IslandPainter({
    required this.shader,
    required this.shape,
    required this.visible,
    required this.radius,
    required this.visibility,
    required this.theme,
    required this.devicePixelRatio,
    this.side,
    this.corners = 4,
  });

  final ui.FragmentShader? shader;
  final Rect shape;
  final Rect visible;
  final double radius;
  final double visibility;
  final MikkyTheme theme;
  final double devicePixelRatio;

  /// Split bubble merged with the island, or null.
  final SideBubble? side;

  /// The corners' power: 4 continuous (the closed pill), 2 round (open,
  /// as the boards and every other surface; 2026-10-02).
  final double corners;

  @override
  void paint(Canvas canvas, Size size) {
    if (visibility <= 0) return;
    final shader = this.shader;
    final side = this.side;
    if (shader == null) {
      final fill = Paint()
        ..color = (theme.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708)).withValues(alpha: visibility);
      canvas.drawRRect(RRect.fromRectAndRadius(shape, Radius.circular(radius)), fill);
      // The bubble, plain too: not fused, but there.
      if (side != null) canvas.drawCircle(side.center, side.radius, fill);
      return;
    }
    final c = shape.center;
    final values = <double>[
      c.dx, c.dy, shape.width / 2, shape.height / 2, // uBox
      radius, // uR
      c.dx, c.dy, 0, // uDrop (not used yet: hidden in the box)
      side?.center.dx ?? c.dx, side?.center.dy ?? c.dy, side?.radius ?? 0, // uSide
      1, side?.smoothness ?? 1, // uK, uKs
      theme.isLight ? 1 : 0, // uLight
      1 / devicePixelRatio, // uPx
      visibility, // uVis
      corners, // uN
    ];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    // Only the island, the bubble and their shadow (mostly below).
    var area = Rect.fromLTRB(visible.left - 60, visible.top - 40, visible.right + 60, visible.bottom + 90);
    if (side != null) area = area.expandToInclude(Rect.fromCircle(center: side.center, radius: side.radius + 60));
    canvas.drawRect(area.intersect(Offset.zero & size), Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(IslandPainter old) =>
      old.shader != shader ||
      old.shape != shape ||
      old.visible != visible ||
      old.radius != radius ||
      old.visibility != visibility ||
      old.theme != theme ||
      old.devicePixelRatio != devicePixelRatio ||
      old.side != side ||
      old.corners != corners;
}

/// The split bubble (Dynamic Island style), as in the prototype: it slides
/// out of the island's end and stays joined by smooth-min while close.
class SideBubble {
  const SideBubble({required this.center, required this.radius, required this.smoothness});

  /// [out]: 0 inside the island, 1 fully out. [anchor]: where it starts (the
  /// island's end), [direction]: where it goes.
  factory SideBubble.at(Offset anchor, Offset direction, double out) {
    final o = out.clamp(0.0, 1.2);
    final join = (1 - (o - .55).abs() * 1.4).clamp(0.0, 1.0);
    return SideBubble(
      center: anchor + direction * (o * 42),
      radius: 4 + 13 * o.clamp(0.0, 1.0),
      smoothness: 1 + 15 * join * (o > .02 ? 1 : 0),
    );
  }

  final Offset center;
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is SideBubble && other.center == center && other.radius == radius && other.smoothness == smoothness;

  @override
  int get hashCode => Object.hash(center, radius, smoothness);
  final double smoothness;
}
