import 'package:flutter/widgets.dart';

import 'motion.dart';
import 'pixel_fx.dart';
import 'tokens.dart';

/// Where we are among pages (the home's apps, redone 2026-10-02): small
/// grey pixels, one per page, and a pixel star in our signature blues on
/// the page shown. Going to another page, the star glides straight there,
/// very smoothly (user request: « tout droit, façon smooth ultra »), a
/// short trail of blue pixels fading behind it while it moves. Always the
/// same place: nothing around it moves. A click on a pixel goes to its
/// page. Still at rest (no loop), nothing when there is one page.
class PageDots extends StatefulWidget {
  const PageDots({super.key, required this.count, required this.page, this.onSelect});

  final int count;
  final int page;
  final ValueChanged<int>? onSelect;

  /// Between two pages; the star's square; the height kept.
  static const step = 16.0, star = 13.0, height = 16.0;

  static double widthFor(int count) => count <= 1 ? 0 : (count - 1) * step + star;

  @override
  State<PageDots> createState() => _PageDotsState();
}

class _PageDotsState extends State<PageDots> with SingleTickerProviderStateMixin {
  late final _glide = AnimationController(vsync: this, duration: const Duration(milliseconds: 460), value: 1);
  late double _fromX = _x(widget.page);
  int? _hover;

  /// Slow out, slow in, no overshoot: a glide.
  static const _ease = Cubic(.45, 0, .2, 1);

  double _x(int i) => PageDots.star / 2 + i.clamp(0, widget.count < 1 ? 0 : widget.count - 1) * PageDots.step;

  double _at(int page, double t) => _fromX + (_x(page) - _fromX) * _ease.transform(t);

  @override
  void didUpdateWidget(PageDots old) {
    super.didUpdateWidget(old);
    if (old.page == widget.page) return;
    // From wherever it is, even mid-way.
    _fromX = _at(old.page, _glide.value);
    if (Motion.reduced(context)) {
      _glide.value = 1;
    } else {
      _glide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  int _indexAt(double dx) => ((dx - PageDots.star / 2) / PageDots.step).round().clamp(0, widget.count - 1);

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 1) return const SizedBox(height: PageDots.height);
    final ui = MikkyUi.of(context);
    final on = widget.onSelect != null;
    // Our signature blues; on black, one step lighter (the darkest would
    // vanish).
    final sig = PixelFxPalette.signatureBlue.levels;
    final blues = ui.isLight ? PixelFxPalette.signatureBlue : PixelFxPalette('Bleus', [Color.lerp(sig[0], const Color(0xFFFFFFFF), .4)!, sig[0], sig[1], sig[2]]);
    return Semantics(
      label: 'Page ${widget.page + 1} sur ${widget.count}',
      child: MouseRegion(
        cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
        onHover: on ? (e) => setState(() => _hover = _indexAt(e.localPosition.dx)) : null,
        onExit: (_) => setState(() => _hover = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: on
              ? (d) {
                  final i = _indexAt(d.localPosition.dx);
                  if (i != widget.page) widget.onSelect!(i);
                }
              : null,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _glide,
              builder: (context, _) {
                final t = _glide.value;
                final x = _at(widget.page, t);
                // A little behind: where the trail starts.
                final behind = _at(widget.page, (t - .08).clamp(0.0, 1.0));
                return CustomPaint(
                  size: Size(PageDots.widthFor(widget.count), PageDots.height),
                  painter: _DotsPainter(
                    count: widget.count,
                    page: widget.page,
                    hover: _hover,
                    starX: x,
                    trail: t < 1 ? x - behind : 0,
                    dot: ui.text3.withValues(alpha: ui.text3.a * .6),
                    dotHover: ui.text2,
                    star: blues,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({
    required this.count,
    required this.page,
    required this.hover,
    required this.starX,
    required this.trail,
    required this.dot,
    required this.dotHover,
    required this.star,
  });

  final int count, page;
  final int? hover;
  final double starX;

  /// How far it went in the last moment, signed: the trail's length.
  final double trail;
  final Color dot, dotHover;
  final PixelFxPalette star;

  static const _pixel = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final paint = Paint();

    // The pages' pixels; the one under the star is hidden by it.
    for (var i = 0; i < count; i++) {
      final x = PageDots.star / 2 + i * PageDots.step;
      if ((x - starX).abs() < PageDots.star / 2 + 1) continue;
      paint.color = i == hover && i != page ? dotHover : dot;
      canvas.drawRect(Rect.fromCenter(center: Offset(x, cy), width: _pixel, height: _pixel), paint);
    }

    // The trail: blue pixels behind it, fainter and smaller further back,
    // as long as it moves fast.
    final length = trail.abs();
    if (length > .5) {
      final dir = trail.sign;
      for (var k = 1; k <= 4; k++) {
        final back = PageDots.star / 2 - 1 + k * length.clamp(0.0, 9.0) / 2.2;
        final fade = (1 - k / 5) * (length / 6).clamp(0.0, 1.0);
        paint.color = star.levels[k < 3 ? 1 : 2].withValues(alpha: fade);
        final side = k < 3 ? 2.0 : 1.5;
        canvas.drawRect(Rect.fromCenter(center: Offset(starX - dir * back, cy), width: side, height: side), paint);
      }
    }

    // The star, its middle size.
    const s = PageDots.star;
    canvas.save();
    canvas.translate(starX - s / 2, cy - s / 2);
    paintPixelGrid(canvas, const Size.square(s), 7, gap: .02, (x, y) {
      final level = pixelLevel(CalmFirework.frame(1, x - 3, y - 3));
      return level == null ? null : star.levels[level];
    });
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.starX != starX || old.trail != trail || old.hover != hover || old.page != page || old.count != count || old.dot != dot || old.star != star;
}
