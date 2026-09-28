import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:mikky_engine/mikky_engine.dart';

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

/// The island's shape, centered on [centerX], glued to the top edge.
class IslandPainter extends CustomPainter {
  IslandPainter({
    required this.shader,
    required this.motion,
    required this.centerX,
    required this.theme,
    required this.devicePixelRatio,
  });

  final ui.FragmentShader? shader;
  final IslandMotion motion;
  final double centerX;
  final MikkyTheme theme;
  final double devicePixelRatio;

  /// The box starts this far above the screen: only the bottom corners show.
  static const _top = -40.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (motion.isGone) return;
    final w = motion.currentWidth, h = motion.currentHeight;
    final shader = this.shader;
    if (shader == null) {
      _paintFallback(canvas, w, h);
      return;
    }
    final halfW = w / 2, halfH = (h - _top) / 2;
    final boxY = (_top + h) / 2;
    final values = <double>[
      centerX, boxY, halfW, halfH, // uBox
      motion.cornerRadius, // uR
      centerX, boxY, 0, // uDrop (not used yet: hidden in the box)
      centerX, boxY, 0, // uSide (not used yet)
      1, 1, // uK, uKs
      theme.isLight ? 1 : 0, // uLight
      1 / devicePixelRatio, // uPx
      motion.visibility, // uVis
    ];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    // Only the island and its shadow, not the whole window.
    final area = Rect.fromLTRB(centerX - halfW - 60, 0, centerX + halfW + 60, h + 90);
    canvas.drawRect(area, Paint()..shader = shader);
  }

  void _paintFallback(Canvas canvas, double w, double h) {
    final r = motion.cornerRadius;
    final shape = RRect.fromLTRBR(centerX - w / 2, -r, centerX + w / 2, h, Radius.circular(r));
    final alpha = motion.visibility;
    canvas.drawRRect(
      shape,
      Paint()..color = (theme.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708)).withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(IslandPainter oldDelegate) => true;
}
