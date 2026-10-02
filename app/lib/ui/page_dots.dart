import 'package:flutter/widgets.dart';

import 'motion.dart';
import 'tokens.dart';

/// Where we are among pages (the home's tiles at the top, 2026-10-02):
/// grey dots, and one dark pill that slides to the page on the
/// selectors' spring, stretched by its speed. A click on a dot goes there.
/// Nothing when there is a single page.
class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.count, required this.page, this.onSelect});

  final int count;
  final int page;
  final ValueChanged<int>? onSelect;

  static const dot = 5.0, pill = 14.0, step = 14.0, height = 16.0;

  static double widthFor(int count) => count <= 1 ? 0 : (count - 1) * step + pill;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox(height: height);
    final ui = MikkyUi.of(context);
    double center(int i) => pill / 2 + i * step;
    return Semantics(
      label: 'Page ${page + 1} sur $count',
      child: SizedBox(
        width: widthFor(count),
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < count; i++)
              Positioned(
                left: center(i) - step / 2,
                top: 0,
                width: step,
                height: height,
                child: PressDown(
                  onDown: onSelect == null || i == page ? null : () => onSelect!(i),
                  child: HoverBuilder(
                    enabled: onSelect != null && i != page,
                    builder: (context, hover) => Center(
                      child: AnimatedContainer(
                        duration: Motion.of(context, Motion.hover),
                        width: dot,
                        height: dot,
                        decoration: BoxDecoration(
                          color: hover ? ui.text2 : ui.text3.withValues(alpha: ui.text3.a * .6),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: SpringValue(
                    target: center(page.clamp(0, count - 1)) - pill / 2,
                    spring: Motion.thumb,
                    builder: (context, x, v) {
                      final stretch = (v.abs() * Motion.thumbStretch * .5).clamp(0.0, 6.0);
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: x - (v < 0 ? stretch : 0),
                            top: (height - dot) / 2,
                            width: pill + stretch,
                            height: dot,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: ui.text, borderRadius: BorderRadius.circular(dot / 2)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
