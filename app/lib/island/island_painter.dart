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
    if (shader == null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(shape, Radius.circular(radius)),
        Paint()..color = (theme.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708)).withValues(alpha: visibility),
      );
      return;
    }
    final c = shape.center;
    final side = this.side;
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

/// Small colored dot inside the split bubble.
class BubbleDotPainter extends CustomPainter {
  BubbleDotPainter({required this.center, required this.radius, required this.color, required this.opacity, required this.glow});

  final Offset center;
  final double radius;
  final Color color;
  final double opacity;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final c = color.withValues(alpha: color.a * opacity);
    if (glow) {
      canvas.drawCircle(center, radius, Paint()
        ..color = c
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
    canvas.drawCircle(center, radius, Paint()..color = c);
  }

  @override
  bool shouldRepaint(BubbleDotPainter old) => true;
}

/// Right end of the compact island: progress ring or check mark (spec §5.3,
/// rule 3), 16 × 16.
class PillIndicatorPainter extends CustomPainter {
  PillIndicatorPainter.ring({required double this.progress, required this.color, required this.track}) : check = false;
  PillIndicatorPainter.check({required this.color})
      : progress = null,
        track = null,
        check = true;

  final double? progress;
  final Color color;
  final Color? track;
  final bool check;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (check) {
      final path = Path()
        ..moveTo(3.5, 8.5)
        ..relativeLineTo(3, 3)
        ..relativeLineTo(6, -7);
      canvas.drawPath(path, stroke..color = color);
      return;
    }
    const c = Offset(8, 8);
    canvas.drawCircle(c, 6, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = track!);
    canvas.drawArc(Rect.fromCircle(center: c, radius: 6), -1.5707963, 6.2831853 * progress!, false, stroke..color = color);
  }

  @override
  bool shouldRepaint(PillIndicatorPainter old) => old.progress != progress || old.color != color || old.check != check;
}
