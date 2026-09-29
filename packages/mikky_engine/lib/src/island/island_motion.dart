import 'dart:math' as math;

import '../anim/spring.dart';

enum IslandShape { hidden, compact, open }

enum IslandLayout { focus, list }

/// The screen edge the island is glued to.
enum IslandEdge {
  /// Top center, wide: the Dynamic Island look.
  top,

  /// Right edge, vertically centered, tall like a phone in portrait.
  right,
}

typedef IslandSize = ({double width, double height});
typedef MikkySpot = ({double x, double y, double radius});

/// Sizes of the island and Mikky's place in it, for one [IslandEdge].
/// Mikky's position is relative to the island's top-left corner.
class IslandMetrics {
  const IslandMetrics._({
    required this.compact,
    required this.focus,
    required this.list,
    required this.hidden,
    required this.compactRadius,
    required this.openRadius,
    required this.mikkyCompact,
    required this.mikkyOpen,
  });

  /// Spec §3: closed 186 × 36, open Focus 430 × 178, List 450 × 180.
  static const top = IslandMetrics._(
    compact: (width: 186, height: 36),
    focus: (width: 430, height: 178),
    list: (width: 450, height: 180),
    hidden: (width: 150, height: 0),
    compactRadius: 18,
    openRadius: 30,
    mikkyCompact: (x: 21, y: 20, radius: 9),
    mikkyOpen: (x: 54, y: 88, radius: 28),
  );

  /// A small tab when closed, a phone-shaped card when open: the small
  /// window of `ux-a.html`, Mikky in small at the top left of its head.
  static const right = IslandMetrics._(
    compact: (width: 64, height: 92),
    focus: (width: 320, height: 560),
    list: (width: 320, height: 560),
    hidden: (width: 0, height: 80),
    compactRadius: 22,
    openRadius: 38,
    mikkyCompact: (x: 32, y: 36, radius: 13),
    mikkyOpen: (x: 30, y: 39, radius: 15),
  );

  static IslandMetrics of(IslandEdge edge) => switch (edge) {
        IslandEdge.top => top,
        IslandEdge.right => right,
      };

  final IslandSize compact, focus, list, hidden;
  final double compactRadius, openRadius;
  final MikkySpot mikkyCompact, mikkyOpen;

  IslandSize open(IslandLayout layout) => layout == IslandLayout.focus ? focus : list;
}

/// The island's size and the place of Mikky in it, driven by springs
/// (spec §3). Lengths are logical pixels.
class IslandMotion {
  IslandMotion({this.edge = IslandEdge.top}) : metrics = IslandMetrics.of(edge) {
    _applyTargets();
    _snapAll();
  }

  final IslandEdge edge;
  final IslandMetrics metrics;

  /// On opening, the depth (away from the edge) follows the length along
  /// the edge with this delay.
  static const openDepthDelay = .045;

  final width = Spring(0, SpringSpec.island);
  final height = Spring(0, SpringSpec.island);
  final radius = Spring(0, SpringSpec.island);
  final progress = Spring(0, SpringSpec.progress);

  IslandShape get shape => _shape;
  IslandShape _shape = IslandShape.hidden;
  IslandLayout get layout => _layout;
  IslandLayout _layout = IslandLayout.focus;

  Spring get _depth => edge == IslandEdge.top ? height : width;
  double? _pendingDepth;
  double _depthDelay = 0;

  void setShape(IslandShape shape, {IslandLayout? layout}) {
    final opening = shape == IslandShape.open && _shape != IslandShape.open;
    _shape = shape;
    _layout = layout ?? _layout;
    _applyTargets(delayDepth: opening);
  }

  void _applyTargets({bool delayDepth = false}) {
    final size = switch (_shape) {
      IslandShape.hidden => metrics.hidden,
      IslandShape.compact => metrics.compact,
      IslandShape.open => metrics.open(_layout),
    };
    width.target = size.width;
    height.target = size.height;
    radius.target = _shape == IslandShape.open ? metrics.openRadius : metrics.compactRadius;
    progress.target = _shape == IslandShape.open ? 1 : 0;
    _pendingDepth = null;
    if (delayDepth) {
      _pendingDepth = _depth.target;
      _depth.target = _depth.value;
      _depthDelay = openDepthDelay;
    }
  }

  void update(double dt) {
    final pending = _pendingDepth;
    if (pending != null) {
      _depthDelay -= dt;
      if (_depthDelay <= 0) {
        _depth.target = pending;
        _pendingDepth = null;
      }
    }
    for (final s in _springs) {
      s.step(dt);
    }
    if (isAtRest) _snapAll();
  }

  List<Spring> get _springs => [width, height, radius, progress];

  void _snapAll() {
    for (final s in _springs) {
      s.snap();
    }
  }

  /// Nothing moves any more: no frame is needed for the island.
  bool get isAtRest => _pendingDepth == null && _springs.every((s) => s.isAtRest(.02));

  /// Fully hidden and still: nothing to draw at all.
  bool get isGone => _shape == IslandShape.hidden && isAtRest;

  double get currentWidth => math.max(0, width.value);
  double get currentHeight => math.max(0, height.value);

  /// Corner radius actually drawn.
  double get cornerRadius => math.max(0, math.min(radius.value, math.min(currentHeight / 2, currentWidth / 2)));

  /// 0 when hidden, 1 from the compact depth on.
  double get visibility => edge == IslandEdge.top
      ? (currentHeight / metrics.compact.height).clamp(0.0, 1.0)
      : (currentWidth / metrics.compact.width).clamp(0.0, 1.0);

  /// Open progress, may overshoot a little.
  double get openness => progress.value.clamp(0.0, 1.1);

  /// Opacity of the compact content ("Mikky" and the indicator).
  double get compactContentOpacity => (1 - openness * 3.2).clamp(0.0, 1.0);

  /// Opacity of the open content (Focus / List views).
  double get openContentOpacity => ((openness - .5) * 2.4).clamp(0.0, 1.0);

  double get mikkyRadius =>
      _lerp(metrics.mikkyCompact.radius, metrics.mikkyOpen.radius, openness.clamp(0.0, 1.05));

  /// Mikky's center, from the island's left edge.
  double get mikkyX => _lerp(metrics.mikkyCompact.x, metrics.mikkyOpen.x, openness.clamp(0.0, 1.0));

  /// Mikky's center, from the island's top edge. At the top of the screen,
  /// Mikky slides up with the island while it hides.
  double get mikkyY =>
      _lerp(metrics.mikkyCompact.y, metrics.mikkyOpen.y, openness.clamp(0.0, 1.0)) +
      (edge == IslandEdge.top ? math.min(0, currentHeight - metrics.compact.height) : 0);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
