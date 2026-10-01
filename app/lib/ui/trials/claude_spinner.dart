import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion.dart';

// A trial, shown on the design boards only: Claude at work, against its
// logo that turns ([SpinningLogo], in use); the user picks one (design.md
// §12, step 1).

/// Claude Code's own « working » star, as its terminal shows it: a dot
/// that grows into a cross, an asterisk, a star, a flower, then back, in
/// Claude's orange (to compare with [SpinningLogo], user request,
/// 2026-09-30: « il manque l'animation de Claude quand il travaille »).
class ClaudeSpinner extends StatelessWidget {
  const ClaudeSpinner({super.key, this.size = 28});

  final double size;

  /// Its steps, there and back: (rays, length, thickness) in fractions of
  /// the size; 0 rays is the dot.
  static const _frames = [(0, .0, .0), (4, .34, .1), (6, .42, .09), (6, .46, .15), (8, .46, .12), (8, .5, .17)];

  @override
  Widget build(BuildContext context) => Looping(
    period: const Duration(milliseconds: 1320),
    frozenAt: .45,
    builder: (context, t) {
      final n = _frames.length;
      // 0 1 2 3 4 5 4 3 2 1: there and back.
      final i = (t * (2 * n - 2)).floor() % (2 * n - 2);
      return CustomPaint(size: Size.square(size), painter: _ClaudeStarPainter(_frames[i < n ? i : 2 * n - 2 - i]));
    },
  );
}

class _ClaudeStarPainter extends CustomPainter {
  _ClaudeStarPainter(this.frame);

  final (int, double, double) frame;

  static const _orange = Color(0xFFD97757);

  @override
  void paint(Canvas canvas, Size size) {
    final (rays, length, thickness) = frame;
    final c = size.center(Offset.zero);
    final s = size.shortestSide;
    final paint = Paint()..color = _orange;
    if (rays == 0) {
      canvas.drawCircle(c, s * .09, paint);
      return;
    }
    paint
      ..strokeWidth = s * thickness
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < rays; k++) {
      final a = k * math.pi * 2 / rays - math.pi / 2;
      canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * s * length, paint);
    }
  }

  @override
  bool shouldRepaint(_ClaudeStarPainter old) => old.frame != frame;
}
