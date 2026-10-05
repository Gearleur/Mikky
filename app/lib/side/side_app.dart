import 'dart:async';

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/agents_service.dart';
import '../agents/enchant.dart';
import '../home/home_view.dart';
import '../overlay/overlay_channel.dart';
import '../ui/backend_status.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart';
import '../ui/thread_page.dart';
import 'agent_page.dart';
import 'brief_page.dart';
import 'hooks_page.dart';
import 'home_screen.dart';
import 'new_agent_page.dart';
import 'session_menu.dart';

/// What the small window needs from the island around it.
class SideHost {
  const SideHost({
    required this.service,
    required this.answer,
    required this.pickFolder,
    required this.showMenu,
    required this.islandMenu,
    this.sound,
  });

  final AgentsService service;

  /// Oui / Non / Toujours to agent [id] (the island makes Mikky react).
  final void Function(String id, AgentAnswer answer) answer;
  final Future<String?> Function(String title) pickFolder;
  final Future<int?> Function(List<MenuEntry> entries) showMenu;

  /// The island's own menu (theme, position, quit…).
  final VoidCallback islandMenu;

  /// Plays one of Mikky's sounds (pages that come and go).
  final void Function(MikkyCue cue)? sound;
}

/// The island's window, at the right edge or at the top (2026-10-02): the
/// home (`HomeScreen`, its Chat the new agent), an agent's page (its
/// thread). Pages are stacked; a new one comes in as an iPhone opens an
/// app (2026-10-05: the slide from the right was « pas cool »): it fades
/// in, growing from 97 % to its size, while the one below fades out,
/// drawing back a little; back, the other way. Under a page the island takes
/// the page's size ([HomeLayout.pageSize]).
class SideApp extends StatefulWidget {
  const SideApp({super.key, required this.host, this.layout = HomeLayout.right, this.onHome});

  final SideHost host;
  final HomeLayout layout;

  /// On the home or not: the island shows Mikky in the head only there.
  final ValueChanged<bool>? onHome;

  @override
  State<SideApp> createState() => SideAppState();
}

class _Page {
  _Page(this.key, this.build);

  final String key;
  final Widget Function() build;
}

class SideAppState extends State<SideApp> with SingleTickerProviderStateMixin {
  /// The pages come and go on the island's own spring (its stiffness,
  /// barely damped more so they do not overshoot), so they arrive with
  /// the island as it grows or shrinks (2026-10-05: one motion, smooth).
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: SpringSpec.island.stiffness, ratio: .95);

  /// Opening: the page below goes out early; the new one comes in a little
  /// later. Back (t from 1 to 0): the page leaves in the first half, the
  /// one below is whole from 55 % of the way (2026-10-05: « le texte ne
  /// s'efface pas assez rapidement pour voir les applications »).
  static const _out = Interval(0, .55), _in = Interval(.15, 1);
  static const _backOut = Interval(.5, 1), _backIn = Interval(.45, 1);

  /// Going back: the other timing (above).
  bool _back = false;

  /// A page comes or goes: the one below is drawn.
  bool _moving = false;

  late final List<_Page> _pages = [_Page('home', _home)];

  /// Agents opened from the history: back among the apps.
  final _recalled = <String>{};

  /// The home keeps its own size under a taller page.
  Widget _home() => Align(
    alignment: Alignment.topLeft,
    child: HomeScreen(
      layout: widget.layout,
      entries: host.service.source.homeEntries,
      canLaunch: host.service.canLaunch,
      open: _open,
      recalled: _recalled,
      recall: (id) {
        setState(() => _recalled.add(id));
        _open(id);
      },
      onMenu: _menu,
    ),
  );

  /// In the notch, Mikky beside the thread, in the middle (the island's).
  MikkyBeside? get _beside => widget.layout.isTop ? MikkyBeside.middle : null;

  /// A new chat (2026-10-05: « comme pour l'agent »): a page as an agent's,
  /// its thread empty; sent, it becomes the agent's page, in place.
  _Page _newChat() => _Page(
    'new',
    () => NewAgentPage(
      host: host,
      back: back,
      mikky: _beside,
      launched: (id) => _replaceTop(_agentPage(id)),
      login: (target, provider, done) => _pushPage(_Page(
        'login',
        () => LoginPage(
          host: host,
          target: target,
          provider: provider,
          back: back,
          done: () {
            back();
            done();
          },
        ),
      )),
    ),
  );

  /// An agent's ··· menu, from a row of the history.
  void _menu(String id) {
    final e = host.service.source.entry(id);
    if (e != null) showSessionMenu(host, e, rename: () => _open('rename:$id'));
  }
  late final AnimationController _t = AnimationController(vsync: this, value: 1);

  // Agents send many small changes while they work (a message comes in
  // pieces): the pages follow at most every 60 ms — the first change at
  // once, the last one never lost.
  static const _settle = Duration(milliseconds: 60);
  Timer? _settling;
  bool _changed = false;

  void _onService() {
    if (_settling != null) {
      _changed = true;
      return;
    }
    setState(() {});
    _settling = Timer(_settle, () {
      _settling = null;
      if (_changed && mounted) {
        _changed = false;
        _onService();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    widget.host.service.addListener(_onService);
  }

  @override
  void didUpdateWidget(SideApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host.service != widget.host.service) {
      oldWidget.host.service.removeListener(_onService);
      widget.host.service.addListener(_onService);
    }
  }
  _Page? _leaving;

  SideHost get host => widget.host;

  bool get onHome => _pages.length == 1 && _leaving == null;

  @override
  void dispose() {
    widget.host.service.removeListener(_onService);
    _settling?.cancel();
    _t.dispose();
    super.dispose();
  }

  /// Runs the move from where it is to [to] on the spring; done, the page
  /// below is put away.
  Future<void> _move(double to) {
    setState(() => _moving = true);
    final reduced = Motion.reduced(context);
    final run = reduced ? _t.animateTo(to, duration: Duration.zero) : _t.animateWith(SpringSimulation(_spring, _t.value, to, 0));
    return run.whenComplete(() {
      if (mounted) setState(() => _moving = false);
    });
  }

  void _open(String what) => switch (what) {
    final w when w.startsWith('alert:') => _pushPage(_Page(
      w,
      () => BriefPage(
        host: host,
        id: w.substring(6),
        back: back,
        openAgent: () => _replaceTop(_agentPage(w.substring(6))),
      ),
    )),
    'hooks' => _pushPage(_Page('hooks', () => HooksPage(host: host, back: back))),
    'hooks:codex' => _pushPage(_Page('hooks:codex', () => HooksPage(host: host, back: back, tool: AgentProvider.codex))),
    'new' => _pushPage(_newChat()),
    final w when w.startsWith('rename:') => _pushPage(_Page(w, () => RenamePage(host: host, id: w.substring(7), back: back))),
    _ => _pushPage(_agentPage(what)),
  };

  _Page _agentPage(String id) => _Page(
    'agent:$id',
    () => AgentPage(host: host, id: id, back: back, rename: () => _open('rename:$id'), mikky: _beside),
  );

  void _pushPage(_Page page) {
    if (_pages.last.key == page.key) return;
    host.sound?.call(MikkyCue.navigate);
    setState(() {
      _pages.add(page);
      _back = false;
    });
    widget.onHome?.call(false);
    _t.value = 0;
    _move(1);
  }

  void back() {
    if (_pages.length < 2 || _leaving != null) return;
    host.sound?.call(MikkyCue.back);
    setState(() {
      _leaving = _pages.removeLast();
      _back = true;
    });
    if (_pages.length == 1) widget.onHome?.call(true);
    _move(0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _leaving = null;
        _back = false;
      });
      _t.value = 1;
    });
  }

  /// The page on top: `home`, `agent:<id>`, `alert:<id>`…
  String get topKey => _pages.last.key;

  /// What agent [id] asks, with its context, from anywhere (an alert at
  /// the right edge).
  void openAlert(String id) {
    if (_pages.last.key == 'alert:$id') return;
    setState(() => _pages.removeRange(1, _pages.length));
    _open('alert:$id');
  }

  /// A page of its own from anywhere (`hooks`: Claude Code's hooks).
  void openPage(String what) {
    if (_pages.last.key == what) return;
    setState(() => _pages.removeRange(1, _pages.length));
    _open(what);
  }

  /// Back to the home without sliding (the island closed under a page
  /// that no longer applies).
  void home() {
    if (_pages.length < 2) return;
    setState(() => _pages.removeRange(1, _pages.length));
    widget.onHome?.call(true);
  }

  /// Opens agent [id]'s page from anywhere (a click on its notification).
  void openAgent(String id) {
    if (_pages.last.key == 'agent:$id') return;
    setState(() => _pages.removeRange(1, _pages.length));
    _open(id);
  }

  /// The new agent becomes its agent page (a short fade, no slide).
  void _replaceTop(_Page page) => setState(() => _pages[_pages.length - 1] = page);

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final top = _leaving ?? _pages.last;
    final below = _leaving != null ? _pages.last : (_pages.length > 1 ? _pages[_pages.length - 2] : null);
    // Built here, once per change — never at each frame of a move.
    Widget page(_Page p) => KeyedSubtree(
      key: ValueKey(p.key),
      child: RepaintBoundary(child: ColoredBox(color: ui.island, child: p.build())),
    );
    final notice = switch (host.service.backend) {
      BackendState.online => null,
      BackendState.connecting => const BackendStatus(title: 'Connexion à Mikky', message: 'Tes sessions arrivent…'),
      BackendState.reconnecting => const BackendStatus(
        title: 'Reconnexion en cours',
        message: 'Le dernier état reste visible. Les actions seront disponibles une fois la connexion rétablie.',
      ),
      BackendState.unavailable => BackendStatus(
        title: 'Moteur indisponible',
        message: host.service.backendError ?? 'La connexion sera réessayée automatiquement.',
        retry: host.service.reconnect,
        warning: true,
      ),
    };
    // The move: the page above fades in growing to its size, the one below
    // fades out drawing back a little; back, the other timing.
    final aboveOpacity = _t.drive(CurveTween(curve: _back ? _backOut : _in));
    final belowOpacity = _t.drive(Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: _back ? _backIn : _out)));
    return Column(
      children: [
        ?notice,
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              // Pages further down keep their state but are not drawn.
              for (final p in _pages)
                if (p != top && p != below) Offstage(child: TickerMode(enabled: false, child: page(p))),
              // Hidden and still at rest, in the same widgets: it keeps
              // its state.
              if (below != null)
                Offstage(
                  offstage: !_moving,
                  child: TickerMode(
                    enabled: _moving,
                    child: FadeTransition(
                      opacity: belowOpacity,
                      child: ScaleTransition(scale: _t.drive(Tween(begin: 1.0, end: 1.015)), alignment: Alignment.topCenter, child: page(below)),
                    ),
                  ),
                ),
              // The same widgets at rest (1, 1): the page keeps its state.
              FadeTransition(
                opacity: aboveOpacity,
                child: ScaleTransition(scale: _t.drive(Tween(begin: .97, end: 1.0)), alignment: Alignment.topCenter, child: page(top)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// « Terminer » on an agent stopped by its limit: no relaunch, no more
/// waiting; it leaves « Travaillent » and the island, and stays as done.
void finishLimit(SideHost host, String id) {
  Enchantments.instance.cancel(id);
  host.service.source.settle(id);
}
