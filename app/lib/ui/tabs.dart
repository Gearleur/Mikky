import 'dart:ui' as dui show ImageFilter;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'feedback.dart';
import 'icons.dart';
import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

/// One tab: an icon, a label (not in the mini bar), and what waits there.
class TabItem {
  const TabItem(this.icon, {this.label, this.count, this.dot = false});

  final String icon;
  final String? label;

  /// A number badge (unread mails…).
  final int? count;

  /// The amber dot (an agent waits for a yes).
  final bool dot;
}

/// `.tabbar`: the floating tab bar (62 px, frosted), or the icons-only
/// mini bar (52 px, 50 px per tab). The white capsule slides with the
/// selectors' spring; the chosen icon pops (500 / 0.45, from 0.78).
/// Kept for later (user, 2026-09-29).
class MTabBar extends StatelessWidget {
  const MTabBar({super.key, required this.items, required this.selected, this.onChanged, this.mini = false});

  final List<TabItem> items;
  final int selected;
  final ValueChanged<int>? onChanged;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final height = mini ? 52.0 : 62.0;
    final radius = height / 2;
    Widget bar(double col) => SizedBox(
      height: height - 10,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: SpringValue(
                target: selected * col,
                spring: Motion.thumb,
                builder: (context, x, v) {
                  final stretch = (v.abs() * Motion.thumbStretch).clamp(0.0, Motion.thumbStretchMax);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: x - (v > 0 ? stretch : 0),
                        top: 0,
                        bottom: 0,
                        width: col + stretch,
                        child: Surface(radius: mini ? 21 : 26, color: ui.thumb, shadows: ui.shThumb),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: col,
                  child: PressDown(
                    onDown: onChanged == null || i == selected ? null : () => onChanged!(i),
                    child: _Tab(item: items[i], on: i == selected, mini: mini),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    final content = mini
        ? SizedBox(width: 50.0 * items.length, child: bar(50))
        : LayoutBuilder(builder: (context, box) => bar(box.maxWidth / items.length));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The frost: what is behind, blurred 20 px and more saturated.
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(filter: _frost, child: const SizedBox.expand()),
          ),
        ),
        Surface(
          radius: radius,
          height: height,
          color: ui.raise,
          shadows: ui.floating,
          padding: const EdgeInsets.all(5),
          child: content,
        ),
      ],
    );
  }

  static final _frost = dui.ImageFilter.compose(outer: _saturate(1.5), inner: dui.ImageFilter.blur(sigmaX: 10, sigmaY: 10));

  static ColorFilter _saturate(double s) {
    const r = .2126, g = .7152, b = .0722;
    return ColorFilter.matrix(<double>[
      r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0, //
      r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0,
      r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }
}

class _Tab extends StatefulWidget {
  const _Tab({required this.item, required this.on, required this.mini});

  final TabItem item;
  final bool on;
  final bool mini;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController.unbounded(vsync: this, value: 1);

  @override
  void didUpdateWidget(_Tab old) {
    super.didUpdateWidget(old);
    if (widget.on && !old.on && !Motion.reduced(context)) {
      _pop.animateWith(SpringSimulation(Motion.pop, .78, 1, 0));
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final color = widget.on ? ui.text : ui.text2;
    final item = widget.item;
    final icon = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pop,
        builder: (context, child) => Transform.scale(scale: _pop.value, child: child),
        child: MikkyIcon(item.icon, size: 21, color: color),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            if (!widget.mini && item.label != null) ...[
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: Motion.fade,
                style: uiText(TextSize.caption, weight: FontWeight.w600, color: color, height: 1.2),
                child: Text(item.label!),
              ),
            ],
          ],
        ),
        if (item.count != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Align(alignment: const Alignment(.42, -1), child: CountBadge(item.count!)),
          ),
        if (item.dot)
          Positioned(
            top: 3,
            left: 0,
            right: 0,
            child: Align(
              alignment: const Alignment(.4, -1),
              child: DotBadge(show: item.dot),
            ),
          ),
      ],
    );
  }
}
