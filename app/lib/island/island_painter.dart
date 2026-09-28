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
  });

  final ui.FragmentShader? shader;
  final Rect shape;
  final Rect visible;
  final double radius;
  final double visibility;
  final MikkyTheme theme;
  final double devicePixelRatio;

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
    final values = <double>[
      c.dx, c.dy, shape.width / 2, shape.height / 2, // uBox
      radius, // uR
      c.dx, c.dy, 0, // uDrop (not used yet: hidden in the box)
      c.dx, c.dy, 0, // uSide (not used yet)
      1, 1, // uK, uKs
      theme.isLight ? 1 : 0, // uLight
      1 / devicePixelRatio, // uPx
      visibility, // uVis
    ];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    // Only the island and its shadow (mostly below), not the whole window.
    final area = Rect.fromLTRB(visible.left - 60, visible.top - 40, visible.right + 60, visible.bottom + 90);
    canvas.drawRect(area.intersect(Offset.zero & size), Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(IslandPainter oldDelegate) => true;
}
