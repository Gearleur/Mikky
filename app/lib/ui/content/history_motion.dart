import 'dart:ui' as dui;

import 'package:flutter/widgets.dart';

import '../../island/island_painter.dart';
import '../foundation/surface.dart';
import '../foundation/tokens.dart';
import '../overlays/sheet.dart';

final Future<dui.FragmentProgram?> historyDetachProgram = _loadProgram();

Future<dui.FragmentProgram?> _loadProgram() async {
  try {
    return await dui.FragmentProgram.fromAsset('shaders/history_detach.frag');
  } catch (error) {
    debugPrint('mikky: history fusion unavailable, plain fallback ($error)');
    return null;
  }
}

/// The island bubble's spring, growth and smooth-min, stretched into a
/// full-height rail. The content remains usable while the forms separate.
class HistoryDetach extends StatelessWidget {
  const HistoryDetach({super.key, required this.navigation, required this.body});

  final Widget navigation, body;

  static const width = 40.0, leading = 52.0, radius = Radii.xl;

  @override
  Widget build(BuildContext context) {
    final out = SheetMotion.detachmentOf(context);
    final ui = MikkyUi.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final bubble = SideBubble.at(
          Offset(leading + width / 2, box.maxHeight / 2),
          const Offset(-leading / 42, 0),
          out,
        );
        final half = bubble.radius * width / 34;
        final rail = Rect.fromCenter(center: bubble.center, width: half * 2, height: box.maxHeight);
        final pane = Rect.fromLTRB(leading, 0, box.maxWidth, box.maxHeight);
        final railRadius = half.clamp(0.0, radius);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: FutureBuilder<dui.FragmentProgram?>(
                  future: historyDetachProgram,
                  builder: (_, loaded) => CustomPaint(
                    painter: _HistoryFusion(
                      shader: loaded.data?.fragmentShader(),
                      pane: pane,
                      rail: rail,
                      railRadius: railRadius,
                      smoothness: bubble.smoothness * width / 17,
                      ui: ui,
                      pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(left: leading, right: 0, top: 0, bottom: 0, child: body),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: width,
              child: Transform.translate(
                key: const ValueKey('history-detach-motion'),
                offset: Offset(bubble.center.dx - width / 2, 0),
                child: ClipRRect(
                  clipper: _RailClip(half, railRadius),
                  child: Opacity(opacity: ((out - .08) / .5).clamp(0.0, 1.0), child: navigation),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RailClip extends CustomClipper<RRect> {
  const _RailClip(this.halfWidth, this.radius);

  final double halfWidth, radius;

  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(
    Rect.fromCenter(center: size.center(Offset.zero), width: halfWidth * 2, height: size.height),
    Radius.circular(radius),
  );

  @override
  bool shouldReclip(_RailClip old) => old.halfWidth != halfWidth || old.radius != radius;
}

class _HistoryFusion extends CustomPainter {
  const _HistoryFusion({
    required this.shader,
    required this.pane,
    required this.rail,
    required this.railRadius,
    required this.smoothness,
    required this.ui,
    required this.pixelRatio,
  });

  final dui.FragmentShader? shader;
  final Rect pane, rail;
  final double railRadius, smoothness, pixelRatio;
  final MikkyUi ui;

  @override
  void paint(Canvas canvas, Size size) {
    // Keep the kit's colours and shadows, including the final still frame.
    for (final (rect, color, corners, shadows) in [
      (rail, ui.well, railRadius, ui.shThumb),
      (pane, ui.island, HistoryDetach.radius, ui.floating),
    ]) {
      canvas.save();
      canvas.translate(rect.left, rect.top);
      SurfacePainter(color: color, radius: corners, shadows: shadows, pixelRatio: pixelRatio).paint(canvas, rect.size);
      canvas.restore();
    }
    final fusion = shader;
    // Smooth-min can only join the surfaces while this gap is small.
    if (fusion == null || pane.left - rail.right >= smoothness / 2) return;
    final values = [
      pane.center.dx,
      pane.center.dy,
      pane.width / 2,
      pane.height / 2,
      rail.center.dx,
      rail.center.dy,
      rail.width / 2,
      rail.height / 2,
      HistoryDetach.radius,
      railRadius,
      smoothness,
      ui.island.r,
      ui.island.g,
      ui.island.b,
      ui.island.a,
      ui.well.r,
      ui.well.g,
      ui.well.b,
      ui.well.a,
      1 / pixelRatio,
    ];
    for (var i = 0; i < values.length; i++) {
      fusion.setFloat(i, values[i]);
    }
    canvas.drawRect((Offset.zero & size).inflate(smoothness), Paint()..shader = fusion);
  }

  @override
  bool shouldRepaint(_HistoryFusion old) =>
      old.shader != shader ||
      old.pane != pane ||
      old.rail != rail ||
      old.railRadius != railRadius ||
      old.ui != ui ||
      old.smoothness != smoothness ||
      old.pixelRatio != pixelRatio;
}
