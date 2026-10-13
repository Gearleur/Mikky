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
import '../home/home_layout.dart';
import '../mikky/mikky_painter.dart';
import '../motion/intro.dart';
import '../overlay/overlay_channel.dart';
import '../settings.dart';
import '../side/home_screen.dart' show watchedTask;
import '../side/session_steps.dart';
import '../side/side_app.dart';
import '../sound/sound_board.dart';
import '../theme.dart';
import '../ui/foundation/motion.dart';
import '../ui/foundation/tokens.dart';
import '../ui/overlays/floating_menu.dart';
import 'compact_view.dart';
import 'content/brief_view.dart';
import 'content/focus_model.dart';
import 'content/focus_views.dart';
import 'deadline_timer.dart';
import 'island_bench.dart';
import 'island_geometry.dart';
import 'island_hotkeys.dart';
import 'island_layers.dart';
import 'island_menu.dart';
import 'island_notifier.dart';
import 'island_painter.dart';

/// The island with Mikky in it, glued to the top or the right edge.
///
/// [IslandMachine] decides everything; this widget feeds it the
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
  List<Agent> get _attentionAgents => _demo ? _source.agents : Enchantments.instance.attentionAgents(_source.agents);
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
  late final _deadlines = DeadlineTimer(_sync);
  late final _notifier = IslandNotifier(_overlay.notify);

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

  /// Mikky's greeting when the app starts (2026-10-06: the pop, chosen on
  /// the boards): when it began (clock time); null once done, or skipped
  /// (fewer animations asked, bench).
  double? _greetAt;

  /// The island opens first; the pop starts this much later.
  static const _greetLead = .35;

  /// After the pop, its layer fades out while the island closes.
  static const _greetFade = .25;

  bool get _greeting => _greetAt != null;

  /// Where in the pop we are (seconds).
  double get _greetT => _clock.now - (_greetAt ?? 0) - _greetLead;

  /// The greeting's layer: full during the pop, then fading out.
  double get _greetOpacity {
    final after = _greetT - Intros.pop.duration;
    return after <= 0 ? 1.0 : (1 - after / _greetFade).clamp(0.0, 1.0);
  }

  Widget? _openContent;
  Object? _openContentKey;

  OverlayChannel get _overlay => widget.overlay;
  IslandEdge get _edge => _motion.edge;

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
    if (widget.bench == null && !ui.PlatformDispatcher.instance.accessibilityFeatures.disableAnimations) {
      _greetAt = _clock.now;
      _motion.setShape(IslandShape.open, layout: IslandLayout.greet);
      // His usual self stays out of sight while he greets.
      _mikkyOpacity = 0;
    }
    unawaited(IslandHotkey.register(_overlay, enabled: widget.settings.hotkeys));
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    if (widget.bench case final bench?) {
      _demo = true;
      _demoSource.addAgent(_clock.now);
      _machine.setAgents(_attentionAgents, _clock.now);
      bench.run(
        describe: () =>
            'fast clock started $_wakes times, decor clock $_calms times, '
            'motion at rest ${_motion.isAtRest}, bubble at rest ${_bubble.isAtRest()}',
        done: _overlay.quit,
      );
    }
    // Real agents move on their own: the island follows them.
    _agentsSub = widget.agents.source.changes.listen((_) {
      if (!_demo && mounted) _sync();
    });
    Enchantments.instance.addListener(_onSpells);
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
    _overlay.onHotkey = null;
    _mikky.onSound = null;
    _agentsSub?.cancel();
    Enchantments.instance.removeListener(_onSpells);
    _deadlines.cancel();
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

  /// Where the island and its parts are, at this frame.
  IslandGeometry get _geo => IslandGeometry(_motion, _bubble.value);

  // --------------------------------------------------------------- engine

  /// Brings the source and the machine to now, then draws and sleeps until
  /// the next deadline.
  void _sync() {
    final now = _clock.now;
    if (_source.advance(now)) _machine.setAgents(_attentionAgents, now);
    _machine.advance(now);
    _react(_director.advance(now));
    _apply();
  }

  void _onSpells() {
    if (_demo || !mounted) return;
    _machine.setAgents(_attentionAgents, _clock.now);
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
    if (_edge == IslandEdge.right &&
        s.openReason == OpenReason.alert &&
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
    _motion.listIdle =
        _edge == IslandEdge.top &&
        !_demo &&
        watchedTask(Enchantments.instance.attentionEntries(widget.agents.source.homeEntries), DateTime.now()) == null;
    final relaid = layout != _motion.layout;
    // While Mikky greets, the island stays open for him.
    if (!_greeting && (s.shape != _motion.shape || relaid)) {
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
    _notifier.update(s.agents, enabled: !_demo && widget.settings.notifications, windowOpen: _sideOpen);
    // Mikky moving to his other place on the home counts too.
    final changed =
        relaid ||
        s.shape != prev.shape ||
        s.bubble != prev.bubble ||
        !_sameAgents(s.agents, prev.agents) ||
        !_motion.isAtRest;
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

  void _schedule() =>
      _deadlines.schedule([_source.nextDeadline, _machine.nextDeadline, _director.nextDeadline], now: _clock.now);

  // --------------------------------------------------------------- inputs

  void _onCursor(Offset cursor) {
    _cursor = cursor;
    _machine.pointer(_clock.now, overIsland: _geo.hit.contains(cursor), atEdge: _geo.hotZone.contains(cursor));
    if (_director.sleeping && _geo.hit.contains(cursor)) _userActive();
    final overMikky = _motion.visibility > 0 && _geo.onMikky(cursor);
    _mikky.hover(overMikky);
    if (overMikky) _mikky.pointerMoved();
    _apply();
  }

  // ------------------------------------------------------ notifications

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
    final id = _notifier.lastAgent;
    _openWindow();
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
    if (!_sideOpen || !_geo.hit.contains(e.localPosition)) return;
    _machine.click(_clock.now);
    _overlay.activate();
    _apply();
  }

  void _onTapUp(TapUpDetails details) {
    final now = _clock.now;
    _userActive();
    final onMikky = _geo.onMikky(details.localPosition) && _mikkyOpacity > .5;
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
    if (_source.answer(agent.id, answer, now)) _machine.setAgents(_attentionAgents, now);
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
    final chosen = IslandMenuItem.byId(
      await _menu(
        islandMenuEntries(
          settings: s,
          demo: _demo,
          canLaunch: widget.agents.canLaunch,
          autostart: autostart,
          autoRelaunch: Enchantments.instance.everywhere,
        ),
      ),
    );
    if (chosen == null) return;
    final now = _clock.now;
    switch (chosen) {
      case IslandMenuItem.quit:
        await _quit();
      case IslandMenuItem.autostart:
        try {
          await widget.agents.setAutostart(!autostart);
        } catch (_) {
          await _menu([const MenuEntry(1, 'Windows n’a pas pu modifier le démarrage automatique')]);
        }
      case IslandMenuItem.stopAll:
        final sure = await _menu([
          const MenuEntry(1, 'Arrêter tous les agents lancés par Mikky'),
          const MenuEntry(2, 'Annuler'),
        ]);
        if (sure == 1) {
          try {
            await widget.agents.stopAll();
          } catch (_) {
            await _menu([const MenuEntry(1, 'Arrêt non confirmé : vérifie la connexion au moteur')]);
          }
        }
      case IslandMenuItem.autoRelaunch:
        Enchantments.instance.everywhere = !Enchantments.instance.everywhere;
      case IslandMenuItem.themeAuto || IslandMenuItem.themeDark || IslandMenuItem.themeLight:
        s.theme = IslandMenuItem.themes[chosen]!;
        unawaited(s.save());
        setState(() {});
      case IslandMenuItem.edgeTop || IslandMenuItem.edgeRight:
        final edge = chosen == IslandMenuItem.edgeTop ? IslandEdge.top : IslandEdge.right;
        if (edge == s.edge) return;
        s.edge = edge;
        unawaited(s.save());
        await _moveTo(edge);
      case IslandMenuItem.demoScenario:
        _demo = true;
        _demoSource.startScenario(now);
        _machine.setAgents(_attentionAgents, now);
        _sync();
      case IslandMenuItem.demoAdd:
        if (!_demo) _demoSource.stop();
        _demo = true;
        _demoSource.addAgent(now);
        _machine.setAgents(_attentionAgents, now);
        _apply();
      case IslandMenuItem.demoStop:
        _demoSource.stop();
        _demo = false;
        _machine.setAgents(_attentionAgents, now);
        _apply();
      case IslandMenuItem.notifications:
        s.notifications = !s.notifications;
        unawaited(s.save());
      case IslandMenuItem.sound:
        _toggleSound();
      case IslandMenuItem.volumeLow || IslandMenuItem.volumeMid || IslandMenuItem.volumeHigh:
        s.volume = IslandMenuItem.volumes[chosen]!;
        unawaited(s.save());
        _sound.play(MikkyCue.select);
      case IslandMenuItem.hooksClaude || IslandMenuItem.hooksCodex:
        _openWindow();
        _sideKey.currentState?.openPage(chosen == IslandMenuItem.hooksClaude ? 'hooks' : 'hooks:codex');
      case IslandMenuItem.hotkeys:
        s.hotkeys = !s.hotkeys;
        unawaited(s.save());
        await IslandHotkey.register(_overlay, enabled: s.hotkeys);
      case IslandMenuItem.tuning:
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

  /// Opens the island (if closed) and gives it the keyboard.
  void _openWindow() {
    if (_snap.shape != IslandShape.open) _machine.click(_clock.now);
    _overlay.activate();
    _apply();
  }

  void _onHotkey(int id) {
    _userActive();
    switch (IslandHotkey.byId(id)) {
      case IslandHotkey.alert:
        final waiting = _snap.agents.where((a) => a.status.needsYou).firstOrNull;
        if (waiting == null) return _onTrayClick();
        _openWindow();
        if (!_demo) _sideKey.currentState?.openAlert(waiting.id);
      case IslandHotkey.toggle:
        _onTrayClick();
      case IslandHotkey.mute:
        _toggleSound();
      case null:
    }
  }

  /// Closes Mikky; the agents keep running in `mikkyd`.
  Future<void> _quit() async {
    await widget.agents.shutdown();
    _overlay.quit();
  }

  /// Moves the window to [edge]; the island takes its current shape there.
  Future<void> _moveTo(IslandEdge edge) async {
    _ticker.stop();
    _greetAt = null;
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

  /// Nothing springs: the island, the bubble and Mikky's fade are still;
  /// he is not greeting.
  bool get _settled =>
      !_greeting && _motion.isAtRest && _bubble.isAtRest() && (_mikkyOpacity == 0 || _mikkyOpacity == 1);

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
    // The greeting is over: the island goes back to what the rules want.
    if (_greeting && _greetT > Intros.pop.duration + _greetFade) {
      _greetAt = null;
      _apply();
    } else if (_greeting && _greetT > Intros.pop.duration && _motion.shape == IslandShape.open) {
      _motion.setShape(_snap.shape, layout: _layoutWanted);
    }

    // The countdown before closing moves every frame.
    if (_snap.openReason == OpenReason.click) {
      _machine.advance(_clock.now);
      _apply();
    }
    _motion.update(dt);
    _bubble.step(dt);
    if (_bubble.isAtRest()) _bubble.snap();

    // Mikky looks at the bubble while it is out, else at the cursor.
    final c = _geo.mikkyCenter;
    final side = _geo.sideBubble;
    final atBubble = side != null && _geo.bubbleOut > .5;
    final (lookX, lookY) = atBubble
        ? (_edge == IslandEdge.top ? (.9, 0.0) : (0.0, .9))
        : Mikky.lookAt(_cursor.dx - c.dx, _cursor.dy - c.dy);
    _mikky.update(dt, lookX: lookX, lookY: lookY, attention: atBubble);
    // On the home, on a request he brings (an alert page), and in the
    // notch on an agent's page, beside the thread (2026-10-05).
    final top = _sideKey.currentState?.topKey ?? '';
    final shownOnPage =
        top.startsWith('alert:') || (_edge == IslandEdge.top && (top.startsWith('agent:') || top == 'new'));
    final mikkyTarget =
        _greeting ||
            ((_edge == IslandEdge.right || _topHomeShown) && _motion.openness > .3 && !_sideHome && !shownOnPage)
        ? 0.0
        : 1.0;
    _mikkyOpacity += (mikkyTarget - _mikkyOpacity) * math.min(1.0, dt * 14);
    if ((mikkyTarget - _mikkyOpacity).abs() < .01) _mikkyOpacity = mikkyTarget;

    _overlay.setHitRect(_geo.hit);
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
        final log = entry?.log;
        final brief = log == null ? briefOfAgent(focus) : briefOf(log, focus.status);
        _openContent = RepaintBoundary(
          child: MikkyUiScope(
            ui: theme.ui,
            child: SizedBox(
              width: width,
              height: open.height - 28,
              child: SingleChildScrollView(
                child: BriefView(
                  key: ValueKey('${focus.id}:${focus.status.name}'),
                  agent: focus,
                  brief: brief,
                  question: log?.question,
                  canAlways: log != null && canAlways(log),
                  queue: s.pendingAlerts,
                  actions: BriefActions(
                    answer: (a) => _answer(focus, a),
                    answerQuestion: entry != null && widget.agents.source.canAnswerQuestion(focus.id)
                        ? (answers) {
                            widget.agents.source.answerQuestion(focus.id, answers);
                            _react(reactionToAnswer(AgentAnswer.allow));
                            _machine.click(_clock.now);
                            _sync();
                          }
                        : null,
                    // Ctrl + click: its terminal or VS Code instead.
                    open: _demo
                        ? null
                        : () => widget.agents.openOrReveal(focus.id, () {
                            if (mounted) _openAgentPage(focus.id);
                          }),
                    terminal: !_demo && widget.agents.source.canLeaveInTerminal(focus.id)
                        ? () => _answer(focus, AgentAnswer.dismiss)
                        : null,
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

  @override
  Widget build(BuildContext context) {
    if (_motion.isGone && _bubble.isAtRest() && _bubble.value == 0) {
      // Nothing to draw; the small window stays alive, asleep.
      return Stack(
        children: [sideWindowLayer(_geo, _theme, opacity: 0, areaKey: _sideArea, content: _side)],
      );
    }
    final theme = _theme;
    final geo = _geo;
    final rect = geo.island;
    final openOpacity = _motion.openContentOpacity;
    final side = geo.sideBubble;
    final countdown = countdownLayer(geo, _snap, theme);
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
                      shape: geo.shape,
                      visible: rect,
                      radius: _motion.cornerRadius,
                      visibility: _motion.visibility,
                      theme: theme,
                      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                      side: side,
                      corners: geo.corners,
                    ),
                  ),
                ),
              ),
              if (side != null && geo.bubbleOut > .3)
                bubbleContentLayer(
                  side,
                  geo.bubbleOut,
                  child: GestureDetector(
                    onTap: () {
                      final id = _snap.focus?.id;
                      _machine.click(_clock.now);
                      _apply();
                      _overlay.activate();
                      if (id != null && !_demo) _sideKey.currentState?.openAlert(id);
                    },
                    child: BubbleAlert(
                      theme: theme,
                      status: _snap.focus?.status ?? AgentStatus.approval,
                      waiting: _snap.pendingAlerts,
                    ),
                  ),
                ),
              if (!_greeting) ...compactLayers(geo, _snap, theme),
              sideWindowLayer(
                geo,
                theme,
                opacity: !_greeting && (_edge == IslandEdge.right || _topHomeShown) ? openOpacity : 0,
                areaKey: _sideArea,
                content: _side,
              ),
              if (_greeting) islandGreeting(geo, theme, t: _greetT, fade: _greetOpacity),
              if (!_greeting && openOpacity > 0 && _edge == IslandEdge.top && !_topHomeShown)
                Positioned(
                  left: rect.left + 104,
                  top: 16,
                  child: IslandReveal(opacity: openOpacity, child: _openContentFor(theme)),
                ),
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
                            center: geo.mikkyCenter,
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
