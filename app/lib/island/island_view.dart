import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../overlay/overlay_channel.dart';
import '../settings.dart';
import '../theme.dart';
import 'content/focus_model.dart';
import 'content/focus_views.dart';
import 'content/parts.dart';
import 'island_painter.dart';

/// Size of the transparent window for each edge: big enough for the open
/// island, the bubble and the shadow, so it never resizes while animating.
Size windowSizeFor(IslandEdge edge) => switch (edge) {
      IslandEdge.top => const Size(560, 320),
      IslandEdge.right => const Size(400, 700),
    };

/// The shader box goes this far past the screen edge: only the corners
/// away from the edge are rounded.
const _pastEdge = 40.0;

const _menuThemeAuto = 1, _menuThemeDark = 2, _menuThemeLight = 3;
const _menuEdgeTop = 4, _menuEdgeRight = 5;
const _menuDemoScenario = 6, _menuDemoAdd = 7, _menuDemoStop = 8, _menuQuit = 9;

/// The island with Mikky in it, glued to the top or the right edge.
///
/// [IslandMachine] decides everything (spec §5.3); this widget feeds it the
/// cursor, clicks and agents, wakes it up at its deadlines, and draws its
/// snapshot. Nothing runs while nothing happens.
class IslandView extends StatefulWidget {
  const IslandView({super.key, required this.overlay, required this.settings, required this.program});

  final OverlayChannel overlay;
  final Settings settings;
  final ui.FragmentProgram? program;

  @override
  State<IslandView> createState() => _IslandViewState();
}

class _IslandViewState extends State<IslandView> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _clock = SystemClock();
  final _source = DemoAgentSource();
  late final IslandMachine _machine = IslandMachine(now: _clock.now);
  late IslandSnapshot _snap = _machine.snapshot;
  Timer? _deadlineTimer;
  double? _deadlineAt;

  late final Ticker _ticker;
  late final ui.FragmentShader? _shader = widget.program?.fragmentShader();
  late IslandMotion _motion = IslandMotion(edge: widget.settings.edge);
  final _bubble = Spring(0, SpringSpec.sideBubble);
  final _mikky = Mikky();
  final _keys = FocusNode(debugLabel: 'island');
  Duration _lastTick = Duration.zero;
  Offset _cursor = const Offset(-10000, -10000);

  Widget? _openContent;
  Object? _openContentKey;

  OverlayChannel get _overlay => widget.overlay;
  IslandEdge get _edge => _motion.edge;
  Size get _window => windowSizeFor(_edge);

  @override
  void initState() {
    super.initState();
    _overlay.onCursor = _onCursor;
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    // Demo mode: the scenario plays once at launch; replay it from the menu.
    _source.startScenario(_clock.now);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlay.onCursor = null;
    _deadlineTimer?.cancel();
    _ticker.dispose();
    _keys.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  MikkyTheme get _theme =>
      MikkyTheme.resolve(widget.settings.theme, WidgetsBinding.instance.platformDispatcher.platformBrightness);

  // ------------------------------------------------------------ geometry

  /// The part of the island on screen, in window coordinates.
  Rect get _islandRect {
    final w = _motion.currentWidth, h = _motion.currentHeight, win = _window;
    return switch (_edge) {
      IslandEdge.top => Rect.fromLTWH(win.width / 2 - w / 2, 0, w, h),
      IslandEdge.right => Rect.fromLTWH(win.width - w, win.height / 2 - h / 2, w, h),
    };
  }

  Rect get _shapeRect {
    final r = _islandRect;
    return switch (_edge) {
      IslandEdge.top => Rect.fromLTRB(r.left, -_pastEdge, r.right, r.bottom),
      IslandEdge.right => Rect.fromLTRB(r.left, r.top, r.right + _pastEdge, r.bottom),
    };
  }

  /// Bumping the cursor into the edge, near the island, brings it out.
  Rect get _hotZone {
    final win = _window;
    return switch (_edge) {
      IslandEdge.top => Rect.fromLTRB(win.width / 2 - 120, -1, win.width / 2 + 120, 10),
      IslandEdge.right => Rect.fromLTRB(win.width - 10, win.height / 2 - 150, win.width + 1, win.height / 2 + 150),
    };
  }

  Offset get _mikkyCenter => _islandRect.topLeft + Offset(_motion.mikkyX, _motion.mikkyY);

  /// How far the split bubble is out: only while the island is closed.
  double get _bubbleOut => _bubble.value.clamp(0.0, 1.2) * (1 - (_motion.openness * 2).clamp(0.0, 1.0));

  /// Top: out of the right end of the pill. Right: out of the bottom of the tab.
  SideBubble? get _sideBubble {
    final out = _bubbleOut;
    if (out < .01 || _motion.visibility <= 0) return null;
    final r = _islandRect;
    return switch (_edge) {
      IslandEdge.top => SideBubble.at(Offset(r.right - 20, _motion.metrics.compact.height / 2), const Offset(1, 0), out),
      IslandEdge.right => SideBubble.at(Offset(r.center.dx, r.bottom - 20), const Offset(0, 1), out),
    };
  }

  Rect get _hitRect {
    if (_motion.visibility <= 0) return Rect.zero;
    final side = _sideBubble;
    final r = _islandRect;
    return side == null ? r : r.expandToInclude(Rect.fromCircle(center: side.center, radius: side.radius));
  }

  // --------------------------------------------------------------- engine

  /// Brings the source and the machine to now, then draws and sleeps until
  /// the next deadline.
  void _sync() {
    final now = _clock.now;
    if (_source.advance(now)) _machine.setAgents(_source.agents, now);
    _machine.advance(now);
    _apply();
  }

  /// Reads the machine's snapshot, reacts to what changed, schedules the
  /// next wake-up.
  void _apply() {
    final prev = _snap;
    final s = _machine.snapshot;
    _snap = s;
    if (s.shape != _motion.shape) {
      _motion.setShape(s.shape);
      if (s.shape == IslandShape.open) _mikky.blink();
    }
    if (s.openReason == OpenReason.alert && (prev.openReason != OpenReason.alert || prev.focus?.id != s.focus?.id)) {
      _mikky.alert();
    }
    if (s.openReason == OpenReason.finished && prev.openReason != OpenReason.finished) _mikky.happy();
    if (s.preview && !prev.preview) {
      _mikky.blink();
      _mikky.twitch();
    }
    if (s.bubble && !prev.bubble) _mikky.twitch();
    _bubble.target = s.bubble ? 1 : 0;
    final changed = s.shape != prev.shape || s.bubble != prev.bubble || !_sameAgents(s.agents, prev.agents);
    if (changed || !_motion.isGone) _wake();
    _schedule();
  }

  /// Agents are immutable: the same objects mean nothing changed.
  static bool _sameAgents(List<Agent> a, List<Agent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  void _schedule() {
    final a = _source.nextDeadline, b = _machine.nextDeadline;
    final next = a == null ? b : (b == null ? a : math.min(a, b));
    if (next == null) {
      _deadlineTimer?.cancel();
      _deadlineAt = null;
      return;
    }
    // A later deadline can wait: the timer already set will fire first and
    // reschedule.
    final at = _deadlineAt;
    if (at != null && at <= next && (_deadlineTimer?.isActive ?? false)) return;
    _deadlineTimer?.cancel();
    _deadlineAt = next;
    final delay = math.max(0, ((next - _clock.now) * 1e6).ceil()) + 2000;
    _deadlineTimer = Timer(Duration(microseconds: delay), () {
      _deadlineAt = null;
      _sync();
    });
  }

  // --------------------------------------------------------------- inputs

  void _onCursor(Offset cursor) {
    _cursor = cursor;
    _machine.pointer(_clock.now, overIsland: _hitRect.contains(cursor), atEdge: _hotZone.contains(cursor));
    _apply();
  }

  void _onTapUp(TapUpDetails details) {
    final now = _clock.now;
    if (_snap.shape != IslandShape.open) {
      _machine.click(now);
    } else if ((details.localPosition - _mikkyCenter).distance < _motion.mikkyRadius * 1.3) {
      _mikky.boop();
      _machine.click(now);
    } else {
      _machine.close(now);
    }
    _apply();
    // The user reached for the island: it may take the keyboard.
    if (_snap.shape == IslandShape.open) {
      _overlay.activate();
      _keys.requestFocus();
    }
  }

  void _answer(Agent agent, AgentAnswer answer) {
    final now = _clock.now;
    if (agent.status == AgentStatus.finished) {
      // "OK" on a finished agent: stop showing it.
      _machine.close(now);
      _apply();
      return;
    }
    // Activity first: once answered, an alert closes the island.
    _machine.click(now);
    if (_source.answer(agent.id, answer, now)) _machine.setAgents(_source.agents, now);
    switch (answer) {
      case AgentAnswer.allow:
        _mikky.happy();
      case AgentAnswer.deny:
        _mikky.twitch();
      case AgentAnswer.retry:
        _mikky.hop(small: true);
      case AgentAnswer.dismiss:
        _mikky.blink();
    }
    _apply();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _snap.shape != IslandShape.open) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _machine.close(_clock.now);
      _apply();
      return KeyEventResult.handled;
    }
    final focus = _snap.focus;
    if (focus != null && focus.status == AgentStatus.approval) {
      if (key == LogicalKeyboardKey.keyY) {
        _answer(focus, AgentAnswer.allow);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyN) {
        _answer(focus, AgentAnswer.deny);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showMenu() async {
    final s = widget.settings;
    final chosen = await _overlay.showMenu([
      MenuEntry(_menuThemeAuto, 'Thème : automatique', checked: s.theme == ThemeChoice.auto),
      MenuEntry(_menuThemeDark, 'Thème : noir', checked: s.theme == ThemeChoice.dark),
      MenuEntry(_menuThemeLight, 'Thème : blanc', checked: s.theme == ThemeChoice.light),
      const MenuEntry.separator(),
      MenuEntry(_menuEdgeTop, 'Position : en haut', checked: s.edge == IslandEdge.top),
      MenuEntry(_menuEdgeRight, 'Position : à droite', checked: s.edge == IslandEdge.right),
      const MenuEntry.separator(),
      const MenuEntry(_menuDemoScenario, 'Démo : relancer le scénario'),
      const MenuEntry(_menuDemoAdd, 'Démo : ajouter un agent'),
      const MenuEntry(_menuDemoStop, 'Démo : tout arrêter'),
      const MenuEntry.separator(),
      const MenuEntry(_menuQuit, 'Quitter'),
    ]);
    final now = _clock.now;
    switch (chosen) {
      case _menuQuit:
        _overlay.quit();
      case _menuThemeAuto || _menuThemeDark || _menuThemeLight:
        s.theme = const {
          _menuThemeAuto: ThemeChoice.auto,
          _menuThemeDark: ThemeChoice.dark,
          _menuThemeLight: ThemeChoice.light,
        }[chosen]!;
        unawaited(s.save());
        setState(() {});
      case _menuEdgeTop || _menuEdgeRight:
        final edge = chosen == _menuEdgeTop ? IslandEdge.top : IslandEdge.right;
        if (edge == s.edge) return;
        s.edge = edge;
        unawaited(s.save());
        await _moveTo(edge);
      case _menuDemoScenario:
        _source.startScenario(now);
        _sync();
      case _menuDemoAdd:
        _source.addAgent(now);
        _machine.setAgents(_source.agents, now);
        _apply();
      case _menuDemoStop:
        _source.stop();
        _machine.setAgents(_source.agents, now);
        _apply();
    }
  }

  /// Moves the window to [edge]; the island takes its current shape there.
  Future<void> _moveTo(IslandEdge edge) async {
    _ticker.stop();
    await _overlay.setPlacement(edge, windowSizeFor(edge));
    if (!mounted) return;
    setState(() {
      _motion = IslandMotion(edge: edge);
      _openContentKey = null;
    });
    _machine.click(_clock.now);
    _apply();
    _mikky.blink();
    _wake();
  }

  // ---------------------------------------------------------------- frames

  void _wake() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero ? 1 / 60 : math.min((elapsed - _lastTick).inMicroseconds / 1e6, 1 / 20);
    _lastTick = elapsed;

    // The countdown before closing moves every frame.
    if (_snap.openReason == OpenReason.click) {
      _machine.advance(_clock.now);
      _apply();
    }
    _motion.update(dt);
    _bubble.step(dt);
    if (_bubble.isAtRest()) _bubble.snap();

    // Mikky looks at the bubble while it is out, else at the cursor.
    final c = _mikkyCenter;
    final side = _sideBubble;
    final (lookX, lookY) = side != null && _bubbleOut > .5
        ? (_edge == IslandEdge.top ? (.9, 0.0) : (0.0, .9))
        : Mikky.lookAt(_cursor.dx - c.dx, _cursor.dy - c.dy);
    _mikky.update(dt, lookX: lookX, lookY: lookY);

    // Hidden and still: no more frames until something happens.
    if (_motion.isGone && _bubble.isAtRest()) _ticker.stop();
    _overlay.setHitRect(_hitRect);
    setState(() {});
  }

  // ----------------------------------------------------------------- build

  /// Built again only when what it shows changes (at most once a second
  /// for the clocks and progress bars), then reused as is on every frame.
  Widget _openContentFor(MikkyTheme theme) {
    final now = _clock.now;
    final s = _snap;
    final key = (
      theme,
      _edge,
      s.content,
      s.focus?.id,
      s.pendingAlerts,
      [for (final a in s.agents) '${a.id}:${a.status.index}:${a.detail}'].join('|'),
      now.floor(),
    );
    if (key != _openContentKey || _openContent == null) {
      _openContentKey = key;
      final text = IslandText.of(s, now);
      final m = _motion.metrics;
      final open = m.open(_motion.layout);
      _openContent = RepaintBoundary(
        child: switch (_edge) {
          IslandEdge.top => FocusWideView(text: text, theme: theme, onAnswer: _answer, width: open.width - 104 - 18),
          IslandEdge.right => FocusPortraitView(
              text: text,
              theme: theme,
              onAnswer: _answer,
              size: Size(open.width, open.height),
              mikkyBottom: m.mikkyOpen.y + m.mikkyOpen.radius,
            ),
        },
      );
    }
    return _openContent!;
  }

  /// Content appears with a fade, a slight blur and a small shift.
  Widget _reveal(double opacity, Widget child) {
    if (opacity <= 0) return const SizedBox.shrink();
    final blur = (1 - opacity) * 2.5;
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, (1 - opacity) * 6),
        child: blur > .05 ? ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: child) : child,
      ),
    );
  }

  /// Right end of the pill: ring, check or number of agents (rule 3).
  Widget? _indicator(MikkyTheme theme) {
    final s = _snap;
    final focus = s.focus;
    if (s.agents.isEmpty || focus == null) return null;
    final count = Text('${s.agents.length}', style: monoStyle(theme, size: 11.5));
    if (s.pendingAlerts > 0) return count;
    if (focus.status == AgentStatus.finished) {
      return CustomPaint(size: const Size(16, 16), painter: PillIndicatorPainter.check(color: theme.status(AgentStatus.finished)));
    }
    final progress = focus.progressAt(_clock.now);
    if (progress != null) {
      return CustomPaint(
        size: const Size(16, 16),
        painter: PillIndicatorPainter.ring(progress: progress, color: theme.status(focus.status), track: theme.faint),
      );
    }
    return count;
  }

  List<Widget> _compactContent(MikkyTheme theme, Rect rect) {
    final opacity = _motion.compactContentOpacity;
    if (opacity <= 0) return const [];
    final name = Text('Mikky', style: sansStyle(theme, size: _edge == IslandEdge.top ? 13 : 11.5, weight: FontWeight.w600));
    switch (_edge) {
      case IslandEdge.top:
        final slideUp = math.min(0.0, _motion.currentHeight - _motion.metrics.compact.height);
        final top = _motion.metrics.compact.height / 2 - 9 + slideUp;
        final indicator = _indicator(theme);
        return [
          Positioned(left: rect.left + 44, top: top, height: 18, child: Opacity(opacity: opacity, child: Center(child: name))),
          if (indicator != null)
            Positioned(
              right: _window.width - rect.right + 14,
              top: top,
              height: 18,
              child: Opacity(opacity: opacity, child: Center(child: indicator)),
            ),
        ];
      case IslandEdge.right:
        return [
          Positioned(
            left: rect.left,
            top: rect.top + 62,
            width: _motion.metrics.compact.width,
            height: 18,
            child: Opacity(opacity: opacity, child: Center(child: name)),
          ),
        ];
    }
  }

  /// Thin line that shrinks during the last 10 s before closing (rule 5).
  Widget? _countdown(MikkyTheme theme, Rect rect) {
    final c = _snap.closeCountdown;
    if (c == null || _motion.openContentOpacity <= 0) return null;
    final r = _motion.cornerRadius;
    final full = rect.width - 2 * r;
    return Positioned(
      left: rect.left + r + full * (1 - c) / 2,
      top: rect.bottom - 5,
      width: full * c,
      height: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.secondary, borderRadius: BorderRadius.circular(1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_motion.isGone && _bubble.isAtRest() && _bubble.value == 0) return const SizedBox.expand();
    final theme = _theme;
    final rect = _islandRect;
    final openOpacity = _motion.openContentOpacity;
    final open = _motion.metrics.open(_motion.layout);
    final side = _sideBubble;
    final bubbleColor = theme.status(_snap.focus?.status ?? AgentStatus.approval);
    final pulse = _snap.focus?.status == AgentStatus.approval ? .75 + .25 * math.sin(_clock.now * 4) : 1.0;
    final countdown = _countdown(theme, rect);
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: _onTapUp,
        onSecondaryTapUp: (_) => _showMenu(),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: IslandPainter(
                  shader: _shader,
                  shape: _shapeRect,
                  visible: rect,
                  radius: _motion.cornerRadius,
                  visibility: _motion.visibility,
                  theme: theme,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  side: side,
                ),
              ),
            ),
            if (side != null && _bubbleOut > .45)
              Positioned.fill(
                child: CustomPaint(
                  painter: BubbleDotPainter(
                    center: side.center + (_edge == IslandEdge.top ? const Offset(2, 0) : const Offset(0, 2)),
                    radius: 4.2 * pulse + 1,
                    color: bubbleColor,
                    opacity: ((_bubbleOut - .45) * 3).clamp(0.0, 1.0),
                    glow: theme.glow,
                  ),
                ),
              ),
            ..._compactContent(theme, rect),
            if (openOpacity > 0)
              switch (_edge) {
                IslandEdge.top => Positioned(left: rect.left + 104, top: 16, child: _reveal(openOpacity, _openContentFor(theme))),
                IslandEdge.right => Positioned(
                    left: rect.left + (rect.width - open.width) / 2,
                    top: rect.top + (rect.height - open.height) / 2,
                    child: _reveal(openOpacity, _openContentFor(theme)),
                  ),
              },
            ?countdown,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: MikkyPainter(
                    geometry: MikkyGeometry.of(_mikky, _motion.mikkyRadius),
                    center: _mikkyCenter,
                    rim: theme.mikkyRim,
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
