import 'dart:math' as math;

import '../anim/spring.dart';

enum IslandShape { hidden, compact, open }

enum IslandLayout { focus, list }

/// The island's size and the place of Mikky in it, driven by springs
/// (spec §3). All lengths are logical pixels; x is relative to the island's
/// left edge, y to the top of the screen.
class IslandMotion {
  IslandMotion() {
    _applyTargets();
    _snapAll();
  }

  static const compactWidth = 186.0;
  static const compactHeight = 36.0;
  static const compactRadius = 18.0;
  static const openRadius = 30.0;
  static const hiddenWidth = 150.0;

  /// On opening, the height follows the width with this delay.
  static const openHeightDelay = .045;

  static (double, double) openSize(IslandLayout layout) => switch (layout) {
        IslandLayout.focus => (430.0, 178.0),
        IslandLayout.list => (450.0, 180.0),
      };

  final width = Spring(0, SpringSpec.island);
  final height = Spring(0, SpringSpec.island);
  final radius = Spring(0, SpringSpec.island);
  final progress = Spring(0, SpringSpec.progress);

  IslandShape get shape => _shape;
  IslandShape _shape = IslandShape.hidden;
  IslandLayout get layout => _layout;
  IslandLayout _layout = IslandLayout.focus;

  double? _pendingHeight;
  double _heightDelay = 0;

  void setShape(IslandShape shape, {IslandLayout? layout}) {
    final opening = shape == IslandShape.open && _shape != IslandShape.open;
    _shape = shape;
    _layout = layout ?? _layout;
    _applyTargets(delayHeight: opening);
  }

  void _applyTargets({bool delayHeight = false}) {
    final (w, h) = switch (_shape) {
      IslandShape.hidden => (hiddenWidth, 0.0),
      IslandShape.compact => (compactWidth, compactHeight),
      IslandShape.open => openSize(_layout),
    };
    width.target = w;
    radius.target = _shape == IslandShape.open ? openRadius : compactRadius;
    progress.target = _shape == IslandShape.open ? 1 : 0;
    if (delayHeight) {
      _pendingHeight = h;
      _heightDelay = openHeightDelay;
    } else {
      _pendingHeight = null;
      height.target = h;
    }
  }

  void update(double dt) {
    final pending = _pendingHeight;
    if (pending != null) {
      _heightDelay -= dt;
      if (_heightDelay <= 0) {
        height.target = pending;
        _pendingHeight = null;
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
  bool get isAtRest => _pendingHeight == null && _springs.every((s) => s.isAtRest(.02));

  /// Fully hidden and still: nothing to draw at all.
  bool get isGone => _shape == IslandShape.hidden && isAtRest;

  double get currentWidth => math.max(0, width.value);
  double get currentHeight => math.max(0, height.value);

  /// Corner radius actually drawn.
  double get cornerRadius => math.max(0, math.min(radius.value, math.min(currentHeight / 2, currentWidth / 2)));

  /// 0 when hidden, 1 from the compact height on.
  double get visibility => (currentHeight / compactHeight).clamp(0.0, 1.0);

  /// Open progress, may overshoot a little.
  double get openness => progress.value.clamp(0.0, 1.1);

  /// Opacity of the compact content ("Mikky" and the right indicator).
  double get compactContentOpacity => (1 - openness * 3.2).clamp(0.0, 1.0);

  /// Opacity of the open content (Focus / List views).
  double get openContentOpacity => ((openness - .5) * 2.4).clamp(0.0, 1.0);

  double get mikkyRadius => _lerp(9, 28, openness.clamp(0.0, 1.05));
  double get mikkyX => _lerp(21, 54, openness.clamp(0.0, 1.0));

  /// While hiding, Mikky slides up with the island.
  double get mikkyY => _lerp(compactHeight / 2 + 2, 88, openness.clamp(0.0, 1.0)) + math.min(0, currentHeight - compactHeight);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
