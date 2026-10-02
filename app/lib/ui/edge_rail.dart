import 'package:flutter/widgets.dart';

import 'surface.dart';
import 'tokens.dart';

/// Which edge of the window a rail is attached to.
enum RailEdge { left, right }

/// A floating capsule attached to an edge of the window (the home's top
/// bar, 2026-10-02): round on the inside, flat and running past the
/// edge on the other side, so it seems to come out of it. The surface of
/// what floats (`raise`, `floating`), as the tab bar next to it. The
/// content keeps [edgePad] from the edge and [innerPad] on the round side.
class EdgeRail extends StatelessWidget {
  const EdgeRail({super.key, required this.edge, required this.child, this.height = 44, this.innerPad = 6, this.edgePad = 14});

  final RailEdge edge;
  final Widget child;
  final double height;
  final double innerPad, edgePad;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final right = edge == RailEdge.right;
    return ClipRect(
      clipper: _EdgeClipper(edge),
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: right ? 0 : -height,
              right: right ? -height : 0,
              top: 0,
              bottom: 0,
              child: RepaintBoundary(child: Surface(color: ui.raise, shadows: ui.floating)),
            ),
            Padding(
              padding: EdgeInsets.only(left: right ? innerPad : edgePad, right: right ? edgePad : innerPad),
              child: Center(widthFactor: 1, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuts only the attached edge; the shadow shows on the three others.
class _EdgeClipper extends CustomClipper<Rect> {
  const _EdgeClipper(this.edge);

  final RailEdge edge;

  @override
  Rect getClip(Size size) => edge == RailEdge.right
      ? Rect.fromLTRB(-40, -40, size.width, size.height + 60)
      : Rect.fromLTRB(0, -40, size.width + 40, size.height + 60);

  @override
  bool shouldReclip(_EdgeClipper old) => old.edge != edge;
}

/// Round discs in a row, overlapping, the first on top: white, the light
/// edge and hairline of the raised controls. [spread] from 0 (overlapping
/// by [overlap] of a disc) to 1 (side by side, 4 px apart).
class DiscStack extends StatelessWidget {
  const DiscStack({super.key, required this.children, this.size = 32, this.overlap = .3, this.spread = 0});

  final List<Widget> children;
  final double size;
  final double overlap;
  final double spread;

  double get _step => size * (1 - overlap) + (size * overlap + 4) * spread;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final n = children.length;
    if (n == 0) return const SizedBox.shrink();
    return SizedBox(
      width: size + (n - 1) * _step,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The first painted last: it stays whole above the others.
          for (var i = n - 1; i >= 0; i--)
            Positioned(
              left: i * _step,
              top: 0,
              child: Surface(
                width: size,
                height: size,
                color: ui.thumb,
                shadows: [...ui.shCtl, ui.highlight, CssShadow(0, 0, 0, ui.line, spread: .7, inset: true)],
                child: Center(child: children[i]),
              ),
            ),
        ],
      ),
    );
  }
}
