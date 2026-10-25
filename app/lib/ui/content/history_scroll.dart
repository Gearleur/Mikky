import 'package:flutter/widgets.dart';

import '../foundation/motion.dart';

/// A lighter wheel for the small history window. Dragging stays native;
/// repeated wheel input accumulates rather than waiting for each move.
class HistoryScroll extends StatefulWidget {
  const HistoryScroll({super.key, required this.child});

  static const wheelScale = .42;
  static const wheelStep = 40.0;
  static const settle = Duration(milliseconds: 120);

  final Widget child;

  @override
  State<HistoryScroll> createState() => _HistoryScrollState();
}

class _HistoryScrollState extends State<HistoryScroll> {
  final _scroll = _HistoryScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(controller: _scroll, child: widget.child);
}

class _HistoryScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _HistoryScrollPosition(physics: physics, context: context, oldPosition: oldPosition);
}

/// Intercept the position's wheel action, not its child pointer events:
/// driven scrolling temporarily excludes the content from hit testing.
class _HistoryScrollPosition extends ScrollPositionWithSingleContext {
  _HistoryScrollPosition({required super.physics, required super.context, super.oldPosition});

  double? _wheelTarget;

  @override
  void beginActivity(ScrollActivity? newActivity) {
    if (newActivity is! _HistoryWheelActivity) _wheelTarget = null;
    super.beginActivity(newActivity);
  }

  @override
  void pointerScroll(double delta) {
    if (delta == 0) {
      goBallistic(0);
      return;
    }
    final step = (delta * HistoryScroll.wheelScale).clamp(-HistoryScroll.wheelStep, HistoryScroll.wheelStep);
    final target = ((_wheelTarget ?? pixels) + step).clamp(minScrollExtent, maxScrollExtent);
    final within = context.notificationContext;
    if (within == null || Motion.reduced(within)) {
      super.jumpTo(target);
    } else {
      beginActivity(
        _HistoryWheelActivity(
          this,
          from: pixels,
          to: target,
          duration: HistoryScroll.settle,
          curve: Curves.easeOutCubic,
          vsync: context.vsync,
        ),
      );
    }
    _wheelTarget = target;
  }
}

/// A small wheel glide keeps rows clickable, unlike a programmatic jump.
class _HistoryWheelActivity extends DrivenScrollActivity {
  _HistoryWheelActivity(
    super.delegate, {
    required super.from,
    required super.to,
    required super.duration,
    required super.curve,
    required super.vsync,
  });

  @override
  bool get shouldIgnorePointer => false;
}
