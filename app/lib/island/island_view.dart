import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/agents_service.dart';
import '../agents/enchant.dart';
import '../mikky/mikky_painter.dart';
import '../overlay/overlay_channel.dart';
import '../settings.dart';
import '../side/side_app.dart';
import '../theme.dart';
import '../ui/feedback.dart';
import '../ui/floating_menu.dart';
import '../ui/pixel_fx.dart';
import '../ui/tokens.dart';
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
const _menuDemoScenario = 6, _menuDemoAdd = 7, _menuDemoStop = 8, _menuQuit = 9, _menuTuning = 10, _menuNotifications = 11;
const _menuAutoRelaunch = 20;

/// The island with Mikky in it, glued to the top or the right edge.
///
/// [IslandMachine] decides everything (spec §5.3); this widget feeds it the
/// cursor, clicks and agents, wakes it up at its deadlines, and draws its
/// snapshot. Nothing runs while nothing happens.
class IslandView extends StatefulWidget {
  const IslandView({
    super.key,
    required this.overlay,
    required this.settings,
    required this.program,
    required this.tuning,
    required this.clock,
    required this.agents,
  });

  final OverlayChannel overlay;

  /// The island's time; the real agents use the same one.
  final SystemClock clock;

  /// Claude and Codex: the real agents, shown unless the demo plays.
  final AgentsService agents;
  final Settings settings;
  final ui.FragmentProgram? program;

  /// Mikky's proportions (from the tuning screen).
  final MikkyTuning tuning;

  @override
  State<IslandView> createState() => _IslandViewState();
}

class _IslandViewState extends State<IslandView> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final SystemClock _clock = widget.clock;
  final _demoSource = DemoAgentSource();

  /// The demo plays (menu « Démo »): the island shows fake agents.
  bool _demo = false;
  AgentSource get _source => _demo ? _demoSource : widget.agents.source;
  StreamSubscription<void>? _agentsSub;

  /// The small window at the right edge. Kept while the island is closed
  /// (not drawn, not ticking), so its page and drafts stay.
  final _sideKey = GlobalKey<SideAppState>();
  late final SideApp _side = SideApp(
    key: _sideKey,
    host: SideHost(
      service: widget.agents,
      answer: _answerId,
      pickFolder: _overlay.pickFolder,
      showMenu: _menu,
      islandMenu: _showMenu,
    ),
    onHome: (home) => setState(() => _sideHome = home),
  );
  bool _sideHome = true;
  late final IslandMachine _machine = IslandMachine(now: _clock.now);
  late IslandSnapshot _snap = _machine.snapshot;

  // The small window's content: our floating menus open inside it.
  final _sideArea = GlobalKey();
  Timer? _deadlineTimer;
  double? _deadlineAt;

  late final Ticker _ticker;
  late final ui.FragmentShader? _shader = widget.program?.fragmentShader();
  late IslandMotion _motion = IslandMotion(edge: widget.settings.edge);
  final _bubble = Spring(0, SpringSpec.sideBubble);
  final _mikky = Mikky();
  final _keys = FocusNode(debugLabel: 'island');
  Duration _lastTick = Duration.zero;

  /// Mikky in the small window's head: only on the home (the other pages
  /// have a back button there).
  double _mikkyOpacity = 1;
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
    _overlay.onOutsideClick = _onOutsideClick;
    _overlay.onTrayClick = _onTrayClick;
    _overlay.onTrayMenu = _showMenu;
    FloatingMenu.track();
    _overlay.onNotificationClick = _onNotificationClick;
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    // Real agents move on their own: the island follows them.
    _agentsSub = widget.agents.source.changes.listen((_) {
      if (!_demo && mounted) _sync();
    });
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlay.onCursor = null;
    _overlay.onOutsideClick = null;
    _overlay.onTrayClick = null;
    _overlay.onTrayMenu = null;
    _overlay.onNotificationClick = null;
    _agentsSub?.cancel();
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
    // Mikky stands for the agent in focus (rule 10).
    _mikky.setState(_mikkyStateFor(s.focus?.status));
    if (s.openReason == OpenReason.alert && prev.openReason == OpenReason.alert && prev.focus?.id != s.focus?.id) {
      // Next alert of the queue, maybe of the same kind: show it anyway.
      _mikky.alert();
    }
    if (s.preview && !prev.preview) {
      _mikky.blink();
      _mikky.twitch();
    }
    if (s.bubble && !prev.bubble) _mikky.twitch();
    _bubble.target = s.bubble ? 1 : 0;
    _notify(s);
    final changed = s.shape != prev.shape || s.bubble != prev.bubble || !_sameAgents(s.agents, prev.agents);
    if (changed || !_motion.isGone) _wake();
    _schedule();
  }

  static MikkyState _mikkyStateFor(AgentStatus? status) => switch (status) {
        null || AgentStatus.idle || AgentStatus.paused => MikkyState.idle,
        AgentStatus.working => MikkyState.working,
        AgentStatus.thinking => MikkyState.thinking,
        AgentStatus.searching => MikkyState.searching,
        AgentStatus.approval => MikkyState.approval,
        AgentStatus.question => MikkyState.question,
        AgentStatus.error => MikkyState.error,
        AgentStatus.finished => MikkyState.finished,
        AgentStatus.rateLimited => MikkyState.rateLimited,
      };

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
    final overMikky = _motion.visibility > 0 && (cursor - _mikkyCenter).distance < _motion.mikkyRadius * 1.3;
    _mikky.hover(overMikky);
    if (overMikky) _mikky.pointerMoved();
    _apply();
  }

  // ------------------------------------------------------ notifications

  /// The state each agent was last notified in.
  final Map<String, AgentStatus> _notified = {};

  /// The agent of the last notification (a click on it opens its page).
  String? _notifiedAgent;

  /// A Windows notification when a real agent starts waiting for the user,
  /// fails or finishes — unless the small window is open (the user is
  /// looking at it). Once per agent and state.
  void _notify(IslandSnapshot s) {
    final ids = {for (final a in s.agents) a.id};
    _notified.removeWhere((id, _) => !ids.contains(id));
    if (_demo || !widget.settings.notifications) return;
    for (final a in s.agents) {
      final body = switch (a.status) {
        AgentStatus.approval => 'Attend ton feu vert${a.detail.isEmpty ? '' : ' : ${a.detail}'}',
        AgentStatus.question => 'Te pose une question${a.detail.isEmpty ? '' : ' : ${a.detail}'}',
        AgentStatus.error => 'Erreur${a.detail.isEmpty ? '' : ' : ${a.detail}'}',
        AgentStatus.finished => a.detail.isEmpty ? 'Terminé' : 'Terminé : ${a.detail}',
        _ => null,
      };
      if (body == null) {
        _notified.remove(a.id);
        continue;
      }
      if (_notified[a.id] == a.status) continue;
      _notified[a.id] = a.status;
      if (_sideOpen) continue;
      _notifiedAgent = a.id;
      _overlay.notify(a.name, body);
    }
  }

  /// A click on the icon in the notification area: open or close.
  void _onTrayClick() {
    final now = _clock.now;
    if (_snap.shape == IslandShape.open) {
      _machine.close(now);
    } else {
      _machine.click(now);
      _overlay.activate();
    }
    _apply();
  }

  /// A click on a notification: the island opens on that agent.
  void _onNotificationClick() {
    final id = _notifiedAgent;
    if (_snap.shape != IslandShape.open) _machine.click(_clock.now);
    _overlay.activate();
    _apply();
    if (id != null && _edge == IslandEdge.right) _sideKey.currentState?.openAgent(id);
  }

  /// A click elsewhere closes the island the user opened (click, hover), like
  /// a popover. An agent waiting for a yes keeps it open until answered.
  void _onOutsideClick() {
    final reason = _snap.openReason;
    if (_snap.shape != IslandShape.open || reason == OpenReason.alert) return;
    _machine.close(_clock.now);
    _apply();
  }

  /// The small window is open: it is an app, clicks in it do not close it.
  bool get _sideOpen => _edge == IslandEdge.right && _snap.shape == IslandShape.open;

  /// Any press on the open small window: activity (it stays open), and the
  /// keyboard for its field.
  void _onPointerDown(PointerDownEvent e) {
    if (!_sideOpen || !_hitRect.contains(e.localPosition)) return;
    _machine.click(_clock.now);
    _overlay.activate();
    _apply();
  }

  void _onTapUp(TapUpDetails details) {
    final now = _clock.now;
    final onMikky = (details.localPosition - _mikkyCenter).distance < _motion.mikkyRadius * 1.3 && _mikkyOpacity > .5;
    if (_snap.shape != IslandShape.open) {
      _machine.click(now);
    } else if (onMikky) {
      _mikky.boop();
      _machine.click(now);
    } else if (_sideOpen) {
      // A click in the small window: its widgets answer it.
      return;
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
      case AgentAnswer.allow || AgentAnswer.allowAlways:
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

  /// Oui / Non from the small window.
  void _answerId(String id, AgentAnswer answer) {
    final agent = _source.agents.where((a) => a.id == id).firstOrNull;
    if (agent != null) return _answer(agent, answer);
    _source.answer(id, answer, _clock.now);
    _sync();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _snap.shape != IslandShape.open) return KeyEventResult.ignored;
    // Typing in the small window counts as activity: it stays open.
    _machine.click(_clock.now);
    final key = event.logicalKey;
    final typing = FocusManager.instance.primaryFocus != _keys;
    if (key == LogicalKeyboardKey.escape) {
      if (typing) {
        // First Escape leaves the field, the second closes.
        _keys.requestFocus();
      } else {
        _machine.close(_clock.now);
      }
      _apply();
      return KeyEventResult.handled;
    }
    // N / Y answer only when no field has the keyboard (typing « y » in a
    // message must never say yes).
    final focus = _snap.focus;
    if (!typing && focus != null && focus.status == AgentStatus.approval) {
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

  /// Our floating menu inside the small window while it is open (user
  /// request, 2026-09-30); Windows' own elsewhere (a right click on the
  /// closed island, the notification area).
  Future<int?> _menu(List<MenuEntry> entries) {
    final side = _sideArea.currentContext;
    if (side != null && _motion.openness > .9) return showFloatingMenu(side, entries);
    return _overlay.showMenu(entries);
  }

  Future<void> _showMenu() async {
    final s = widget.settings;
    final chosen = await _menu([
      MenuEntry(_menuThemeAuto, 'Thème : automatique', checked: s.theme == ThemeChoice.auto),
      MenuEntry(_menuThemeDark, 'Thème : noir', checked: s.theme == ThemeChoice.dark),
      MenuEntry(_menuThemeLight, 'Thème : blanc', checked: s.theme == ThemeChoice.light),
      const MenuEntry.separator(),
      MenuEntry(_menuEdgeTop, 'Position : en haut', checked: s.edge == IslandEdge.top),
      MenuEntry(_menuEdgeRight, 'Position : à droite', checked: s.edge == IslandEdge.right),
      const MenuEntry.separator(),
      MenuEntry(_menuDemoScenario, _demo ? 'Démo : relancer le scénario' : 'Démo : lancer le scénario'),
      const MenuEntry(_menuDemoAdd, 'Démo : ajouter un agent'),
      if (_demo) const MenuEntry(_menuDemoStop, 'Démo : arrêter (retour aux vrais agents)'),
      const MenuEntry(_menuTuning, 'Réglage de Mikky…'),
      MenuEntry(_menuNotifications, 'Notifications', checked: s.notifications),
      // Agents stopped by a subscription's limit relaunched by themselves
      // (« Ensorcelé »); the violet star after « Agents » while on.
      MenuEntry(_menuAutoRelaunch, 'Relance automatique', checked: Enchantments.instance.everywhere),
      const MenuEntry.separator(),
      const MenuEntry(_menuQuit, 'Quitter'),
    ]);
    final now = _clock.now;
    switch (chosen) {
      case _menuQuit:
        await _quit();
      case _menuAutoRelaunch:
        Enchantments.instance.everywhere = !Enchantments.instance.everywhere;
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
        _demo = true;
        _demoSource.startScenario(now);
        _machine.setAgents(_source.agents, now);
        _sync();
      case _menuDemoAdd:
        if (!_demo) _demoSource.stop();
        _demo = true;
        _demoSource.addAgent(now);
        _machine.setAgents(_source.agents, now);
        _apply();
      case _menuDemoStop:
        _demoSource.stop();
        _demo = false;
        _machine.setAgents(_source.agents, now);
        _apply();
      case _menuNotifications:
        s.notifications = !s.notifications;
        unawaited(s.save());
      case _menuTuning:
        // A normal window, in its own process (see windows/runner/main.cpp).
        unawaited(Process.start(Platform.resolvedExecutable, const ['--tuning'], mode: ProcessStartMode.detached));
    }
  }

  static const _quitYes = 1;

  /// Quitting stops the agents Mikky runs (no `mikkyd` yet): asks first
  /// when some are at work.
  Future<void> _quit() async {
    final working = widget.agents.working;
    if (working > 0) {
      final sure = await _menu([
        MenuEntry(_quitYes, working == 1 ? 'Quitter et arrêter l’agent au travail' : 'Quitter et arrêter les $working agents au travail'),
        const MenuEntry.separator(),
        const MenuEntry(2, 'Annuler'),
      ]);
      if (sure != _quitYes) return;
    }
    await widget.agents.shutdown();
    _overlay.quit();
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
    final atBubble = side != null && _bubbleOut > .5;
    final (lookX, lookY) = atBubble
        ? (_edge == IslandEdge.top ? (.9, 0.0) : (0.0, .9))
        : Mikky.lookAt(_cursor.dx - c.dx, _cursor.dy - c.dy);
    _mikky.update(dt, lookX: lookX, lookY: lookY, attention: atBubble);
    final mikkyTarget = _edge == IslandEdge.right && _motion.openness > .3 && !_sideHome ? 0.0 : 1.0;
    _mikkyOpacity += (mikkyTarget - _mikkyOpacity) * math.min(1.0, dt * 14);
    if ((mikkyTarget - _mikkyOpacity).abs() < .01) _mikkyOpacity = mikkyTarget;

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
      final open = _motion.metrics.open(_motion.layout);
      // At the top only: on the right, the island shows the small window.
      _openContent = RepaintBoundary(
        child: FocusWideView(text: text, theme: theme, onAnswer: _answer, width: open.width - 104 - 18),
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

  /// The state that matters most among [agents]: waiting for you, then an
  /// error, a limit, work, done; null when there are none.
  static UiStatus? _mostPressing(List<Agent> agents) {
    const order = [UiStatus.approval, UiStatus.error, UiStatus.limited, UiStatus.working, UiStatus.thinking, UiStatus.finished, UiStatus.sleeping];
    UiStatus? best;
    for (final a in agents) {
      final st = UiStatus.of(a.status);
      if (best == null || order.indexOf(st) < order.indexOf(best)) best = st;
    }
    return best;
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
        // Under Mikky, the firework of the most pressing state among the
        // agents (user request, 2026-09-30); his name when there are none.
        final top = _mostPressing(_snap.agents);
        return [
          Positioned(
            left: rect.left,
            top: rect.top + 62,
            width: _motion.metrics.compact.width,
            height: 18,
            child: Opacity(
              opacity: opacity,
              child: Center(
                child: top == null
                    ? name
                    : MikkyUiTheme(ui: theme.isLight ? MikkyUi.light : MikkyUi.dark, child: StatusFx(top, size: 18)),
              ),
            ),
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

  /// The small window, cut to the island's current shape while it grows.
  /// [shown]: drawn and ticking; otherwise kept, not drawn, not ticking
  /// (0 % CPU when the island is hidden).
  Widget _sideWindow(MikkyTheme theme, Rect rect, double opacity) {
    final shown = opacity > 0;
    final ui = theme.isLight ? MikkyUi.light : MikkyUi.dark;
    final open = _motion.metrics.open(_motion.layout);
    return Positioned.fromRect(
      rect: shown ? rect : Rect.fromLTWH(rect.left, rect.top, open.width, open.height),
      child: Offstage(
        offstage: !shown,
        child: TickerMode(
          enabled: shown,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_motion.cornerRadius),
            child: OverflowBox(
              minWidth: open.width,
              maxWidth: open.width,
              minHeight: open.height,
              maxHeight: open.height,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - opacity) * 6),
                  child: MikkyUiTheme(
                    ui: ui,
                    child: DefaultTextStyle(style: uiText(14, color: ui.text), child: KeyedSubtree(key: _sideArea, child: _side)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_motion.isGone && _bubble.isAtRest() && _bubble.value == 0) {
      // Nothing to draw; the small window stays alive, asleep.
      return _edge == IslandEdge.right ? Stack(children: [_sideWindow(_theme, _islandRect, 0)]) : const SizedBox.expand();
    }
    final theme = _theme;
    final rect = _islandRect;
    final openOpacity = _motion.openContentOpacity;
    final side = _sideBubble;
    final bubbleColor = theme.status(_snap.focus?.status ?? AgentStatus.approval);
    final pulse = _snap.focus?.status == AgentStatus.approval ? .75 + .25 * math.sin(_clock.now * 4) : 1.0;
    final countdown = _countdown(theme, rect);
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerDown: _onPointerDown,
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
            if (_edge == IslandEdge.right) _sideWindow(theme, rect, openOpacity),
            if (openOpacity > 0 && _edge == IslandEdge.top)
              Positioned(left: rect.left + 104, top: 16, child: _reveal(openOpacity, _openContentFor(theme))),
            ?countdown,
            if (_mikkyOpacity > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _mikkyOpacity,
                    child: CustomPaint(
                      painter: MikkyPainter(
                        geometry: MikkyGeometry.of(_mikky, _motion.mikkyRadius, tuning: widget.tuning),
                        center: _mikkyCenter,
                        rim: theme.mikkyRim,
                        statusColor: theme.status,
                        foreground: theme.foreground,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
