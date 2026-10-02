import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'motion.dart';
import 'pixel_fx.dart';
import 'tokens.dart';

/// Where we are among pages (the home's apps, redone 2026-10-02): small
/// grey pixels, one per page, and a pixel star on the page shown. Going to
/// another page, the star hops there on a little arc, grows while it flies,
/// squashes as it lands and throws four sparks. Always the same place:
/// nothing around it moves, the hop is drawn over. A click on a pixel goes
/// to its page. Still at rest (no loop), nothing when there is one page.
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
  late final _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 560), value: 1);
  late double _fromX = _x(widget.page);
  int? _hover;

  double _x(int i) => PageDots.star / 2 + i.clamp(0, math.max(0, widget.count - 1)) * PageDots.step;

  /// Where the star is drawn now: on its way, with the slight overshoot of
  /// the release.
  double get _starX => _fromX + (_x(widget.page) - _fromX) * _ease.transform(_hop.value);

  static const _ease = Cubic(.3, 1.3, .5, 1);

  @override
  void didUpdateWidget(PageDots old) {
    super.didUpdateWidget(old);
    if (old.page == widget.page) return;
    // From wherever it is, even mid-flight.
    _fromX = _fromXAt(old, _hop.value);
    if (Motion.reduced(context)) {
      _hop.value = 1;
    } else {
      _hop.forward(from: 0);
    }
  }

  double _fromXAt(PageDots old, double t) => _fromX + (_x(old.page) - _fromX) * _ease.transform(t);

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  int _indexAt(double dx) => ((dx - PageDots.star / 2) / PageDots.step).round().clamp(0, widget.count - 1);

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 1) return const SizedBox(height: PageDots.height);
    final ui = MikkyUi.of(context);
    final on = widget.onSelect != null;
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
              animation: _hop,
              builder: (context, _) => CustomPaint(
                size: Size(PageDots.widthFor(widget.count), PageDots.height),
                painter: _DotsPainter(
                  count: widget.count,
                  page: widget.page,
                  hover: _hover,
                  t: _hop.value,
                  starX: _starX,
                  distance: (_x(widget.page) - _fromX).abs() / PageDots.step,
                  dot: ui.text3.withValues(alpha: ui.text3.a * .6),
                  dotHover: ui.text2,
                  star: PixelFxPalette('Encre', [ui.text, ui.text, ui.text2, ui.text3]),
                  spark: ui.text2,
                ),
              ),
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
    required this.t,
    required this.starX,
    required this.distance,
    required this.dot,
    required this.dotHover,
    required this.star,
    required this.spark,
  });

  final int count, page;
  final int? hover;

  /// The hop, 0 (leaving) to 1 (landed and still).
  final double t;
  final double starX;

  /// How many pages it hops over: higher and longer for more.
  final double distance;
  final Color dot, dotHover, spark;
  final PixelFxPalette star;

  static const _pixel = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final flying = t < 1;
    // The arc: up and down, a little higher for a long hop.
    final lift = flying ? math.sin(math.pi * (t / .82).clamp(0.0, 1.0)) * math.min(9.0, 4 + 2.5 * distance) : 0.0;
    final starY = cy - lift;
    final paint = Paint();

    // The pages' pixels; the one under the star is hidden by it.
    for (var i = 0; i < count; i++) {
      final x = PageDots.star / 2 + i * PageDots.step;
      if ((x - starX).abs() < PageDots.star / 2 && lift < 3) continue;
      paint.color = i == hover && i != page ? dotHover : dot;
      canvas.drawRect(Rect.fromCenter(center: Offset(x, cy), width: _pixel, height: _pixel), paint);
    }

    // The star: bigger while it flies, squashed small as it lands, then
    // its middle size.
    final frame = !flying ? 1 : (t < .1 ? 1 : (t < .74 ? 2 : (t < .88 ? 0 : 1)));
    const s = PageDots.star;
    canvas.save();
    canvas.translate(starX - s / 2, starY - s / 2);
    paintPixelGrid(canvas, const Size.square(s), 7, gap: .02, (x, y) {
      final level = pixelLevel(CalmFirework.frame(frame, x - 3, y - 3));
      return level == null ? null : star.levels[level];
    });
    canvas.restore();

    // Four sparks off its diagonals as it lands, flying out and fading.
    if (flying && t > .76) {
      final k = ((t - .76) / .24).clamp(0.0, 1.0);
      final r = 6 + 5 * k;
      paint.color = spark.withValues(alpha: spark.a * (1 - k));
      for (final (dx, dy) in const [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
        canvas.drawRect(Rect.fromCenter(center: Offset(starX + dx * r * .75, cy + dy * r * .75), width: 2, height: 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.t != t || old.starX != starX || old.hover != hover || old.page != page || old.count != count || old.dot != dot || old.star.levels.first != star.levels.first;
}
