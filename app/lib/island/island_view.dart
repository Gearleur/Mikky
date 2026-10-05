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
import '../home/home_view.dart';
import '../side/home_screen.dart' show watchedTask;
import '../side/session_steps.dart';
import '../side/side_app.dart';
import '../sound/sound_board.dart';
import '../theme.dart';
import '../ui/floating_menu.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart';
import 'content/brief_view.dart';
import 'content/focus_model.dart';
import 'content/focus_views.dart';
import 'compact_view.dart';
import 'content/parts.dart';
import 'island_painter.dart';

/// Size of the transparent window for each edge: big enough for the open
/// island, the bubble and the shadow, so it never resizes while animating.
Size windowSizeFor(IslandEdge edge) => switch (edge) {
      // At the top, the notch is 700 wide (2026-10-05), up to 380 high
      // for an agent's page: room for their shadow.
      IslandEdge.top => const Size(840, 480),
      // At the right, up to 344 × 520 (an agent's page): room for its
      // shadow on the left.
      IslandEdge.right => const Size(420, 700),
    };

/// The shader box goes this far past the screen edge: only the corners
/// away from the edge are rounded.
const _pastEdge = 40.0;

const _menuThemeAuto = 1, _menuThemeDark = 2, _menuThemeLight = 3;
const _menuEdgeTop = 4, _menuEdgeRight = 5;
const _menuDemoScenario = 6, _menuDemoAdd = 7, _menuDemoStop = 8, _menuQuit = 9, _menuTuning = 10, _menuNotifications = 11;
const _menuAutoRelaunch = 20;
const _menuStopAll = 12;
const _menuAutostart = 13;
const _menuHooks = 19, _menuHooksCodex = 21;
const _menuSound = 14, _menuVolumeLow = 15, _menuVolumeMid = 16, _menuVolumeHigh = 17, _menuHotkeys = 18;

/// Global shortcuts (Ctrl + Alt + …): ids for [OverlayChannel.setHotkeys].
const _hotkeyAlert = 1, _hotkeyToggle = 2, _hotkeyMute = 3;
const _modCtrlAlt = 2 | 1;
const _vkA = 0x41, _vkSpace = 0x20, _vkM = 0x4D;

/// The island with Mikky in it, glued to the top or the right edge.
///
/// [IslandMachine] decides everything (spec §5.3); this widget feeds it the
/// cursor, clicks and agents, wakes it up at its deadlines, and draws its
/// snapshot. Nothing runs while nothing happens.
/// `--bench` (development): the island with one made-up agent at work, to
/// measure its CPU in a steady state; `--fast` keeps 60 frames a second as
/// the island did before it rested on the decor clock.
enum IslandBench { calm, fast }

class IslandView extends StatefulWidget {
  const IslandView({
    super.key,
    required this.overlay,
    required this.settings,
    required this.program,
    required this.tuning,
    required this.clock,
    required this.agents,
    this.bench,
  });

  final IslandBench? bench;

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

  /// The island's window — the home and its pages — at the right and,
  /// since 2026-10-02, at the top. Kept while the island is closed (not
  /// drawn, not ticking), so its page and drafts stay.
  final _sideKey = GlobalKey<SideAppState>();
  late final _sideHost = SideHost(
    service: widget.agents,
    answer: _answerId,
    pickFolder: _overlay.pickFolder,
    showMenu: _menu,
    islandMenu: _showMenu,
    sound: (cue) => _sound.play(cue),
  );
  Widget get _side => SideApp(
    key: _sideKey,
    host: _sideHost,
    layout: _edge == IslandEdge.top ? HomeLayout.top : HomeLayout.right,
    onHome: (home) {
      _sideHome = home;
      _apply();
    },
  );
  bool _sideHome = true;

  /// At the top: the focus view for an agent that needs the user (Oui /
  /// Non, as before). Else, both edges: the home, another size under a
  /// page (an agent's; at the right, the agent that asks opens there).
  IslandLayout get _layoutWanted => switch (_edge) {
    IslandEdge.top when _snap.openReason == OpenReason.alert && !_forcePage => IslandLayout.focus,
    _ => _sideHome ? IslandLayout.list : IslandLayout.page,
  };

  /// The window is what the open island shows at the top (not an alert).
  bool get _topHomeShown => _edge == IslandEdge.top && _motion.layout != IslandLayout.focus;
  late final IslandMachine _machine = IslandMachine(now: _clock.now);
  late IslandSnapshot _snap = _machine.snapshot;

  /// The director saw the agents at least once.
  bool _directed = false;

  /// At the top, « Voir l'agent » from a request: the window, not the
  /// request, until the island closes.
  bool _forcePage = false;

  // The small window's content: our floating menus open inside it.
  final _sideArea = GlobalKey();
  Timer? _deadlineTimer;
  double? _deadlineAt;

  /// Fast frames (60 a second) while something springs; see [_wake].
  late final Ticker _ticker;

  /// Mikky's idle life on the decor clock (30 a second) while nothing else
  /// moves; see [_animate].
  bool _calm = false;
  Duration? _calmLast;

  /// `--bench`: how often each clock took over.
  int _wakes = 0, _calms = 0;
  late final ui.FragmentShader? _shader = widget.program?.fragmentShader();
  late IslandMotion _motion = IslandMotion(edge: widget.settings.edge);
  final _bubble = Spring(0, SpringSpec.sideBubble);
  final _mikky = Mikky();

  /// How Mikky reacts to the agents, and when he sleeps.
  final _director = MikkyDirector();
  late final SoundBoard _sound = SoundBoard(_overlay, widget.settings);
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
    _overlay.onHotkey = _onHotkey;
    _mikky.onSound = _sound.play;
    _sound.preload();
    _sound.play(MikkyCue.hello);
    unawaited(_setHotkeys());
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    if (widget.bench != null) {
      _demo = true;
      _demoSource.addAgent(_clock.now);
      _machine.setAgents(_source.agents, _clock.now);
      _runBench();
    }
    // Real agents move on their own: the island follows them.
    _agentsSub = widget.agents.source.changes.listen((_) {
      if (!_demo && mounted) _sync();
    });
    _sync();
  }

  /// Counts the frames from 4 s to 16 s, writes them to
  /// `%TEMP%\mikky-bench.txt`, then quits.
  void _runBench() {
    final timings = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> t) => timings.addAll(t);
    Timer(const Duration(seconds: 4), () {
      SchedulerBinding.instance.addTimingsCallback(collect);
      Timer(const Duration(seconds: 12), () {
        SchedulerBinding.instance.removeTimingsCallback(collect);
        double avg(Duration Function(ui.FrameTiming) f) =>
            timings.isEmpty ? 0 : timings.map((t) => f(t).inMicroseconds).reduce((a, b) => a + b) / timings.length / 1000;
        final line = '${widget.bench!.name}: ${(timings.length / 12).toStringAsFixed(1)} frames/s, '
            'build ${avg((t) => t.buildDuration).toStringAsFixed(2)} ms, raster ${avg((t) => t.rasterDuration).toStringAsFixed(2)} ms, '
            'fast clock started $_wakes times, decor clock $_calms times, motion at rest ${_motion.isAtRest}, bubble at rest ${_bubble.isAtRest()}';
        File('${Platform.environment['TEMP']}/mikky-bench.txt').writeAsStringSync('$line\n', mode: FileMode.append);
        _overlay.quit();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlay.onCursor = null;
    _overlay.onOutsideClick = null;
    _overlay.onTrayClick = null;
    _overlay.onTrayMenu = null;
    _overlay.onNotificationClick = null;
    _overlay.onHotkey = null;
    _mikky.onSound = null;
    _agentsSub?.cancel();
    _deadlineTimer?.cancel();
    _ticker.dispose();
    _leaveCalm();
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

  /// The island's corners: continuous while closed (the pill), round once
  /// open, like the boards (user, 2026-10-02: « les bords des planches
  /// sont mieux »), sliding from one to the other as it opens.
  double get _corners => 4 - 2 * _motion.openness.clamp(0.0, 1.0);

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
      IslandEdge.right => SideBubble.at(compactBubbleAnchor(r), const Offset(0, 1), out),
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
    _react(_director.advance(now));
    _apply();
  }

  /// Mikky does [r]; its sound plays.
  void _react(MikkyReaction r) {
    if (r.isEmpty) return;
    _mikky.react(r);
    final cue = r.cue;
    if (cue != null) _sound.play(cue);
  }

  /// The user is here: Mikky wakes up if he slept.
  void _userActive() => _react(_director.user(_clock.now));

  /// Reads the machine's snapshot, reacts to what changed, schedules the
  /// next wake-up.
  void _apply() {
    final prev = _snap;
    final s = _machine.snapshot;
    _snap = s;
    if (_edge == IslandEdge.right && s.openReason == OpenReason.alert &&
        (prev.shape != IslandShape.open || prev.focus?.id != s.focus?.id)) {
      final id = s.focus?.id;
      if (id != null && !_demo) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _snap.shape == IslandShape.open && _snap.focus?.id == id) {
            _sideKey.currentState?.openAlert(id);
          }
        });
      }
    }
    // The small window closes: its menus with it, and a request that was
    // answered or left (the next opening shows the home).
    if (prev.shape == IslandShape.open && s.shape != IslandShape.open) {
      FloatingMenu.dismissAll();
      _forcePage = false;
      if (_sideKey.currentState?.topKey.startsWith('alert:') ?? false) _sideKey.currentState?.home();
      _sound.play(MikkyCue.close);
    }
    if (prev.shape != IslandShape.open && s.shape == IslandShape.open) _sound.play(MikkyCue.open);
    final layout = _layoutWanted;
    // The notch with nothing at work: Mikky takes his bigger place there,
    // as the home draws it (`HomeLayout.top`).
    _motion.listIdle = _edge == IslandEdge.top && !_demo && watchedTask(widget.agents.source.homeEntries, DateTime.now()) == null;
    final relaid = layout != _motion.layout;
    if (s.shape != _motion.shape || relaid) {
      final opening = s.shape != _motion.shape && s.shape == IslandShape.open;
      _motion.setShape(s.shape, layout: layout);
      if (opening) _mikky.blink();
      if (relaid) FloatingMenu.dismissAll();
    }
    // Mikky stands for the agent in focus (rule 10), and reacts to every
    // agent that changed (reactions.dart).
    if (!_sameAgents(s.agents, prev.agents) || prev.focus?.id != s.focus?.id || !_directed) {
      _directed = true;
      for (final (:agentId, :reaction) in _director.agents(s.agents, s.focus, _clock.now)) {
        // The others only make their sound; Mikky moves for his own.
        if (agentId.isEmpty || agentId == s.focus?.id) {
          _react(reaction);
        } else if (reaction.cue case final cue?) {
          _sound.play(cue);
        }
      }
    }
    _mikky.setState(_director.state);
    if (s.openReason == OpenReason.alert && prev.openReason == OpenReason.alert && prev.focus?.id != s.focus?.id) {
      // Next alert of the queue, maybe of the same kind: show it anyway.
      _mikky.alert();
    }
    if (s.preview && !prev.preview) {
      _mikky.blink();
      _mikky.twitch();
      _sound.play(MikkyCue.peek);
    }
    if (s.bubble && !prev.bubble) _mikky.twitch();
    _bubble.target = s.bubble ? 1 : 0;
    _notify(s);
    // Mikky moving to his other place on the home counts too.
    final changed = relaid || s.shape != prev.shape || s.bubble != prev.bubble || !_sameAgents(s.agents, prev.agents) || !_motion.isAtRest;
    if (changed || !_settled) {
      _wake();
    } else {
      _animate();
    }
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
    double? next;
    for (final t in [_source.nextDeadline, _machine.nextDeadline, _director.nextDeadline]) {
      if (t != null && (next == null || t < next)) next = t;
    }
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
    if (_director.sleeping && _hitRect.contains(cursor)) _userActive();
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
    if (id == null) return;
    final needsYou = _source.agents.where((a) => a.id == id).firstOrNull?.status.needsYou ?? false;
    needsYou ? _sideKey.currentState?.openAlert(id) : _sideKey.currentState?.openAgent(id);
  }

  /// Closing hides the screen, never answers or cancels a pending permission.
  void _onOutsideClick() {
    if (_snap.shape != IslandShape.open) return;
    _machine.close(_clock.now);
    _apply();
  }

  /// The small window (or the top home) is open: it is an app, clicks in
  /// it do not close it.
  bool get _sideOpen => _snap.shape == IslandShape.open && (_edge == IslandEdge.right || _topHomeShown);

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
    _userActive();
    final onMikky = (details.localPosition - _mikkyCenter).distance < _motion.mikkyRadius * 1.3 && _mikkyOpacity > .5;
    if (_snap.shape != IslandShape.open) {
      _machine.click(now);
    } else if (onMikky) {
      // A click on Mikky once open: a little slap (Mochi's rule).
      _mikky.slap();
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
    _react(reactionToAnswer(answer));
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
    _userActive();
    // Typing in the small window counts as activity: it stays open.
    _machine.click(_clock.now);
    final key = event.logicalKey;
    final typing = FocusManager.instance.primaryFocus != _keys;
    if (key == LogicalKeyboardKey.escape) {
      if (typing) {
        // First Escape leaves the field, the second closes.
        _keys.requestFocus();
      } else if (_sideOpen && !_sideHome) {
        // A page: back to the home.
        _sideKey.currentState?.back();
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
    final inWindow = _edge == IslandEdge.right || _topHomeShown;
    if (side != null && inWindow && _motion.openness > .9) return showFloatingMenu(side, entries);
    return _overlay.showMenu(entries);
  }

  Future<void> _showMenu() async {
    final s = widget.settings;
    final autostart = widget.agents.autostartEnabled;
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
      MenuEntry(_menuSound, 'Sons', checked: s.sound),
      if (s.sound) ...[
        MenuEntry(_menuVolumeLow, 'Volume : bas', checked: s.volume <= .3),
        MenuEntry(_menuVolumeMid, 'Volume : moyen', checked: s.volume > .3 && s.volume < .8),
        MenuEntry(_menuVolumeHigh, 'Volume : fort', checked: s.volume >= .8),
      ],
      MenuEntry(_menuHotkeys, 'Raccourcis Ctrl + Alt (A, Espace, M)', checked: s.hotkeys),
      // Agents stopped by a subscription's limit relaunched by themselves
      // (« Ensorcelé »); the violet star after « Agents » while on.
      MenuEntry(_menuAutoRelaunch, 'Relance automatique', checked: Enchantments.instance.everywhere),
      if (widget.agents.canLaunch) const MenuEntry(_menuHooks, 'Hooks Claude Code…'),
      if (widget.agents.canLaunch) const MenuEntry(_menuHooksCodex, 'Hooks Codex…'),
      if (widget.agents.canLaunch)
        MenuEntry(_menuAutostart, 'Moteur au démarrage de Windows', checked: autostart),
      const MenuEntry.separator(),
      if (widget.agents.canLaunch) const MenuEntry(_menuStopAll, 'Arrêter tous les agents de Mikky…'),
      MenuEntry(_menuQuit, 'Fermer Mikky · les agents continuent'),
    ]);
    final now = _clock.now;
    switch (chosen) {
      case _menuQuit:
        await _quit();
      case _menuAutostart:
        try { await widget.agents.setAutostart(!autostart); }
        catch (_) { await _menu([const MenuEntry(1, 'Windows n’a pas pu modifier le démarrage automatique')]); }
      case _menuStopAll:
        final sure = await _menu([
          const MenuEntry(1, 'Arrêter tous les agents lancés par Mikky'),
          const MenuEntry(2, 'Annuler'),
        ]);
        if (sure == 1) {
          try { await widget.agents.stopAll(); }
          catch (_) { await _menu([const MenuEntry(1, 'Arrêt non confirmé : vérifie la connexion au moteur')]); }
        }
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
      case _menuSound:
        _toggleSound();
      case _menuVolumeLow || _menuVolumeMid || _menuVolumeHigh:
        s.volume = const {_menuVolumeLow: .2, _menuVolumeMid: .5, _menuVolumeHigh: 1.0}[chosen]!;
        unawaited(s.save());
        _sound.play(MikkyCue.select);
      case _menuHooks || _menuHooksCodex:
        if (_snap.shape != IslandShape.open) _machine.click(_clock.now);
        _overlay.activate();
        _apply();
        _sideKey.currentState?.openPage(chosen == _menuHooks ? 'hooks' : 'hooks:codex');
      case _menuHotkeys:
        s.hotkeys = !s.hotkeys;
        unawaited(s.save());
        await _setHotkeys();
      case _menuTuning:
        // A normal window, in its own process (see windows/runner/main.cpp).
        unawaited(Process.start(Platform.resolvedExecutable, const ['--tuning'], mode: ProcessStartMode.detached));
    }
  }


  void _toggleSound() {
    final s = widget.settings;
    s.sound = !s.sound;
    unawaited(s.save());
    if (s.sound) {
      _sound.preload();
      _sound.play(MikkyCue.select);
    }
  }

  /// Ctrl + Alt + A: to the request waiting; Espace: open or close;
  /// M: sounds on or off. Windows refuses one taken by another app: it
  /// is then left out, said once in the console.
  Future<void> _setHotkeys() async {
    final keys = widget.settings.hotkeys
        ? const [(_hotkeyAlert, _modCtrlAlt, _vkA), (_hotkeyToggle, _modCtrlAlt, _vkSpace), (_hotkeyMute, _modCtrlAlt, _vkM)]
        : const <(int, int, int)>[];
    try {
      final refused = await _overlay.setHotkeys(keys);
      if (refused.isNotEmpty) debugPrint('mikky: shortcuts taken by another app: $refused');
    } on MissingPluginException {
      // Tests and the boards: no native window.
    }
  }

  void _onHotkey(int id) {
    _userActive();
    switch (id) {
      case _hotkeyAlert:
        final waiting = _snap.agents.where((a) => a.status.needsYou).firstOrNull;
        if (waiting == null) {
          _onTrayClick();
          return;
        }
        if (_snap.shape != IslandShape.open) _machine.click(_clock.now);
        _overlay.activate();
        _apply();
        if (!_demo) _sideKey.currentState?.openAlert(waiting.id);
      case _hotkeyToggle:
        _onTrayClick();
      case _hotkeyMute:
        _toggleSound();
    }
  }

  /// Quitting stops the agents Mikky runs (no `mikkyd` yet): asks first
  /// when some are at work.
  Future<void> _quit() async {
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

  /// Nothing springs: the island, the bubble and Mikky's fade are still.
  bool get _settled =>
      _motion.isAtRest && _bubble.isAtRest() && (_mikkyOpacity == 0 || _mikkyOpacity == 1);

  /// Hidden and still: no frames at all until something happens.
  bool get _gone => _motion.isGone && _bubble.isAtRest();

  /// Something moves: fast frames.
  void _wake() {
    _leaveCalm();
    if (!_ticker.isActive) {
      _wakes++;
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  /// Keeps Mikky alive without asking for fast frames.
  void _animate() {
    if (_ticker.isActive || _calm || _gone) return;
    if (!_settled || widget.bench == IslandBench.fast) return _wake();
    _calm = true;
    _calms++;
    _calmLast = null;
    DecorClock.listen(_onCalmTick);
  }

  void _leaveCalm() {
    if (!_calm) return;
    _calm = false;
    DecorClock.unlisten(_onCalmTick);
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero ? 1 / 60 : math.min((elapsed - _lastTick).inMicroseconds / 1e6, 1 / 20);
    _lastTick = elapsed;
    _step(dt);
    if (_gone) {
      _ticker.stop();
    } else if (_settled && widget.bench != IslandBench.fast) {
      _ticker.stop();
      _animate();
    }
  }

  void _onCalmTick() {
    final now = DecorClock.now.value;
    final dt = _calmLast == null ? 1 / DecorClock.fps : math.min((now - _calmLast!).inMicroseconds / 1e6, 1 / 10);
    _calmLast = now;
    _step(dt, calm: true);
    if (!_settled) {
      _wake();
    } else if (_gone) {
      _leaveCalm();
    }
  }

  /// One frame of the island. [calm]: on the decor clock; with Mikky out
  /// of sight and no countdown, nothing to draw.
  void _step(double dt, {bool calm = false}) {

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
    // On the home, and on a request he brings (an alert page).
    final onAlert = _sideKey.currentState?.topKey.startsWith('alert:') ?? false;
    final mikkyTarget = (_edge == IslandEdge.right || _topHomeShown) && _motion.openness > .3 && !_sideHome && !onAlert ? 0.0 : 1.0;
    _mikkyOpacity += (mikkyTarget - _mikkyOpacity) * math.min(1.0, dt * 14);
    if ((mikkyTarget - _mikkyOpacity).abs() < .01) _mikkyOpacity = mikkyTarget;

    _overlay.setHitRect(_hitRect);
    if (calm && _mikkyOpacity == 0 && _snap.closeCountdown == null) return;
    setState(() {});
  }

  // ----------------------------------------------------------------- build

  /// Built again only when what it shows changes (at most once a second
  /// for the clocks and progress bars, and at each event of the agent in
  /// focus), then reused as is on every frame.
  Widget _openContentFor(MikkyTheme theme) {
    final now = _clock.now;
    final s = _snap;
    final focus = s.focus;
    final entry = focus == null || _demo ? null : widget.agents.source.entry(focus.id);
    final key = (
      theme,
      _edge,
      s.content,
      focus?.id,
      s.pendingAlerts,
      [for (final a in s.agents) '${a.id}:${a.status.index}:${a.detail}'].join('|'),
      now.floor(),
      entry?.log.version,
      _demo ? null : widget.agents.source.hookAskOf(focus?.id ?? '')?.id,
    );
    if (key != _openContentKey || _openContent == null) {
      _openContentKey = key;
      final open = _motion.metrics.open(_motion.layout);
      final width = open.width - 104 - 18;
      if (focus == null || s.content == IslandContent.empty) {
        // At the top only: on the right, the island shows the small window.
        _openContent = RepaintBoundary(
          child: FocusWideView(text: IslandText.of(s, now), theme: theme, onAnswer: _answer, width: width),
        );
      } else {
        // What Mikky brings: the request with its task (2026-10-04).
        final ui = theme.isLight ? MikkyUi.light : MikkyUi.dark;
        final log = entry?.log;
        final hook = _demo ? null : widget.agents.source.hookAskOf(focus.id);
        var brief = log == null ? briefOfAgent(focus) : briefOf(log, focus.status);
        if (hook != null) brief = brief.withRequest(hook.request, title: hook.description);
        _openContent = RepaintBoundary(
          child: MikkyUiTheme(
            ui: ui,
            child: DefaultTextStyle(
              style: uiText(14, color: ui.text),
              child: SizedBox(
                width: width,
                height: open.height - 28,
                child: SingleChildScrollView(
                  child: BriefView(
                    key: ValueKey('${focus.id}:${focus.status.name}'),
                    agent: focus,
                    brief: brief,
                    question: hook == null ? log?.question : null,
                    canAlways: hook == null && log != null && canAlways(log),
                    queue: s.pendingAlerts,
                    actions: BriefActions(
                      answer: (a) => _answer(focus, a),
                      answerQuestion: entry != null && entry.live
                          ? (answers) {
                              widget.agents.source.answerQuestion(focus.id, answers);
                              _react(reactionToAnswer(AgentAnswer.allow));
                              _machine.click(_clock.now);
                              _sync();
                            }
                          : null,
                      open: _demo ? null : () => _openAgentPage(focus.id),
                      terminal: hook == null ? null : () => _answer(focus, AgentAnswer.dismiss),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return _openContent!;
  }

  /// From the request at the top to the agent's page (the island's window).
  void _openAgentPage(String id) {
    _machine.click(_clock.now);
    _forcePage = true;
    _apply();
    _sideKey.currentState?.openAgent(id);
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
        // Under Mikky, the state of the agent he stands for; his name
        // when there are none, or while the bubble shows it.
        return [
          Positioned(
            left: rect.left,
            top: rect.top + 57,
            width: _motion.metrics.compact.width,
            height: 18,
            child: Opacity(
              opacity: opacity,
              child: Center(child: CompactUnderMikky(theme: theme, status: _snap.bubble ? null : _snap.focus?.status)),
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
  Widget _sideWindow(MikkyTheme theme, Rect rect, double opacity, Widget content) {
    final shown = opacity > 0;
    final ui = theme.isLight ? MikkyUi.light : MikkyUi.dark;
    final open = _motion.metrics.open(_motion.layout);
    return Positioned.fromRect(
      rect: shown ? rect : Rect.fromLTWH(rect.left, rect.top, open.width, open.height),
      child: Offstage(
        offstage: !shown,
        child: TickerMode(
          enabled: shown,
          // Cut to the island's own shape (the shader's continuous
          // corners, flat against the screen's edge): a page over it — the
          // history's dark — fills the island to its corners (2026-10-02).
          child: ClipPath(
            clipper: IslandClip(_shapeRect.shift(-rect.topLeft), _motion.cornerRadius, _corners),
            // The same shape as a rounded rectangle: blurs behind the pages
            // (the field's foot, the history's dark) stay inside it, even
            // while the island grows (2026-10-05).
            child: ClipRRect(
              clipper: _RoundClip(_shapeRect.shift(-rect.topLeft), _motion.cornerRadius),
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
                      child: DefaultTextStyle(style: uiText(14, color: ui.text), child: KeyedSubtree(key: _sideArea, child: content)),
                    ),
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
      return Stack(children: [_sideWindow(_theme, _islandRect, 0, _side)]);
    }
    final theme = _theme;
    final rect = _islandRect;
    final openOpacity = _motion.openContentOpacity;
    final side = _sideBubble;
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
              // Own layer: Mikky moving every frame does not redraw the island.
              child: RepaintBoundary(
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
                    corners: _corners,
                  ),
                ),
              ),
            ),
            if (side != null && _bubbleOut > .45)
              Positioned(
                left: side.center.dx - 10,
                top: side.center.dy - 10,
                width: 20,
                height: 20,
                child: GestureDetector(
                  onTap: () {
                    final id = _snap.focus?.id;
                    _machine.click(_clock.now);
                    _apply();
                    _overlay.activate();
                    if (id != null && !_demo) _sideKey.currentState?.openAlert(id);
                  },
                  child: Opacity(
                    opacity: ((_bubbleOut - .45) * 3).clamp(0.0, 1.0),
                    child: BubbleStatus(theme: theme, status: _snap.focus?.status ?? AgentStatus.approval),
                  ),
                ),
              ),
            ..._compactContent(theme, rect),
            _sideWindow(theme, rect, _edge == IslandEdge.right || _topHomeShown ? openOpacity : 0, _side),
            if (openOpacity > 0 && _edge == IslandEdge.top && !_topHomeShown)
              Positioned(left: rect.left + 104, top: 16, child: _reveal(openOpacity, _openContentFor(theme))),
            ?countdown,
            if (_mikkyOpacity > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _mikkyOpacity,
                    child: RepaintBoundary(
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
              ),
          ],
        ),
      ),
      ),
    );
  }
}

/// The island's shape in a child of it: [shape] (in the child's
/// coordinates, past the screen's edge) with the shader's corners — a
/// curve of radius [radius] and power [power] (2: a circle's).
/// The island's shape as a rounded rectangle (see [IslandClip]).
class _RoundClip extends CustomClipper<RRect> {
  const _RoundClip(this.shape, this.radius);

  final Rect shape;
  final double radius;

  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(shape, Radius.circular(math.max(0.0, math.min(radius, shape.shortestSide / 2))));

  @override
  bool shouldReclip(_RoundClip old) => old.shape != shape || old.radius != radius;
}

class IslandClip extends CustomClipper<Path> {
  const IslandClip(this.shape, this.radius, [this.power = 2]);

  final Rect shape;
  final double radius, power;

  @override
  Path getClip(Size size) {
    final r = math.max(0.0, math.min(radius, shape.shortestSide / 2));
    if (r == 0) return Path()..addRect(shape);
    final path = Path();
    // Each corner from its center: (cos t, sin t) raised to the power
    // 2 / n lies on |x|ⁿ + |y|ⁿ = 1.
    const steps = 12;
    void corner(Offset c, double from) {
      for (var i = 0; i <= steps; i++) {
        final t = from + math.pi / 2 * i / steps;
        final x = math.cos(t), y = math.sin(t);
        final p = c + Offset(x.sign * math.pow(x.abs(), 2 / power), y.sign * math.pow(y.abs(), 2 / power)) * r;
        if (i == 0 && from == math.pi) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }

    corner(Offset(shape.left + r, shape.top + r), math.pi);
    corner(Offset(shape.right - r, shape.top + r), 1.5 * math.pi);
    corner(Offset(shape.right - r, shape.bottom - r), 0);
    corner(Offset(shape.left + r, shape.bottom - r), .5 * math.pi);
    return path..close();
  }

  @override
  bool shouldReclip(IslandClip old) => old.shape != shape || old.radius != radius || old.power != power;
}
