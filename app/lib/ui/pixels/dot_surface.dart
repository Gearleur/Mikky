import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';

/// A surface of dots, like Nothing's dot matrix (2026-10-12, chosen for a
/// diff's code: « la version claire pour le clair, la noire pour le
/// noir »): the window's own colour — white in light, black in dark — with
/// a grid of faint dots (1 px every [step] px: a very light grey in light,
/// pale in dark), round corners and a hairline. [child] goes on it.
class DotSurface extends StatelessWidget {
  const DotSurface({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// One dot every [step] px, from [step] / 2: a surface drawn in pieces
  /// whose heights are whole steps goes on from one piece to the next.
  static const step = 6.0;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: DotSurfacePainter(MikkyUi.of(context)),
    child: Padding(padding: padding, child: child),
  );
}

/// Paints a [DotSurface] in [ui]'s colours, or one piece of it — the rows
/// of a long list: its round ends only in the [first] and [last] pieces —
/// with [fill] blended in (a tint, a hover). Each piece but the last
/// reaches one pixel into the next, opaque: when Windows scales the screen
/// (125 %), no thin line of the window shows between two pieces
/// (2026-10-12, « enlève les lignes entre chaque ligne »).
class DotSurfacePainter extends CustomPainter {
  DotSurfacePainter(this.ui, {this.first = true, this.last = true, this.fill});

  final MikkyUi ui;
  final bool first, last;
  final Color? fill;

  static const _radius = Radii.lg;

  RRect _shape(Rect r) => RRect.fromRectAndCorners(
    r,
    topLeft: Radius.circular(first ? _radius : 0),
    topRight: Radius.circular(first ? _radius : 0),
    bottomLeft: Radius.circular(last ? _radius : 0),
    bottomRight: Radius.circular(last ? _radius : 0),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final background = ui.isLight ? ui.thumb : ui.island;
    final fill = this.fill;
    canvas.drawRRect(
      _shape(Rect.fromLTRB(0, 0, size.width, size.height + (last ? 0 : 1))),
      Paint()..color = fill == null ? background : Color.alphaBlend(fill, background),
    );
    // The dots.
    final shape = _shape(Offset.zero & size);
    canvas.save();
    canvas.clipRRect(shape);
    final dots = Paint()
      ..color = ui.isLight ? ui.text3.withValues(alpha: .22) : ui.text.withValues(alpha: .1)
      ..isAntiAlias = false;
    const step = DotSurface.step;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), dots);
      }
    }
    canvas.restore();
    // The hairline: its sides; its top and bottom only at its ends.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-1, first ? -1 : 0, size.width + 1, size.height + 1));
    canvas.drawRRect(
      _shape(
        Rect.fromLTRB(.5, first ? .5 : -_radius, size.width - .5, last ? size.height - .5 : size.height + _radius),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ui.line,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(DotSurfacePainter old) =>
      old.ui != ui || old.first != first || old.last != last || old.fill != fill;
}
