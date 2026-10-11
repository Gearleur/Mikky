import 'package:flutter/widgets.dart';

import '../ui/foundation/surface.dart';
import '../ui/foundation/tokens.dart';
import 'home_layout.dart';

/// The home's window on the boards: the island's color and shadow, flat
/// on the side of the screen's edge (the top for the top, the right for
/// the right), round elsewhere. Drawn as the island: one rounded surface
/// running past that edge, cut there.
class HomeFrame extends StatelessWidget {
  const HomeFrame({super.key, required this.layout, required this.child, this.size});

  final HomeLayout layout;
  final Widget child;

  /// Another size than the home's (a page: [HomeLayout.pageSize]).
  final Size? size;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final top = layout.isTop, past = layout.radius;
    final r = Radius.circular(layout.radius);
    return ClipRect(
      clipper: _ScreenEdge(top),
      child: SizedBox.fromSize(
        size: size ?? layout.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: top ? -past : 0,
              right: top ? 0 : -past,
              bottom: 0,
              child: Surface(color: ui.island, radius: layout.radius, shadows: ui.islandShadow),
            ),
            Positioned.fill(
              child: ClipRRect(
                borderRadius: top ? BorderRadius.vertical(bottom: r) : BorderRadius.horizontal(left: r),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuts the side against the screen's edge; the shadow shows elsewhere.
class _ScreenEdge extends CustomClipper<Rect> {
  const _ScreenEdge(this.top);

  final bool top;

  @override
  Rect getClip(Size size) => top
      ? Rect.fromLTRB(-80, 0, size.width + 80, size.height + 100)
      : Rect.fromLTRB(-80, -80, size.width, size.height + 100);

  @override
  bool shouldReclip(_ScreenEdge old) => old.top != top;
}
