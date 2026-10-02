import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/agents_service.dart';
import '../agents/enchant.dart';
import '../home/home_view.dart';
import '../overlay/overlay_channel.dart';
import '../ui/backend_status.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart';
import 'agent_page.dart';
import 'home_screen.dart';
import 'new_agent_page.dart';
import 'session_menu.dart';

/// What the small window needs from the island around it.
class SideHost {
  const SideHost({required this.service, required this.answer, required this.pickFolder, required this.showMenu, required this.islandMenu});

  final AgentsService service;

  /// Oui / Non / Toujours to agent [id] (the island makes Mikky react).
  final void Function(String id, AgentAnswer answer) answer;
  final Future<String?> Function(String title) pickFolder;
  final Future<int?> Function(List<MenuEntry> entries) showMenu;

  /// The island's own menu (theme, position, quit…).
  final VoidCallback islandMenu;
}

/// The island's window, at the right edge or at the top (2026-10-02): the
/// home (`HomeScreen`, its Chat the new agent), an agent's page (Suivi /
/// Chat). Pages are stacked; a new one slides in from the right (380 ms),
/// the one below moves 28 % left and dims. At the top, the island grows
/// a little under a page ([HomeLayout.pageSize]).
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
  static const _push = Duration(milliseconds: 380);
  static const _curve = Cubic(.2, .9, .25, 1);

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
      chat: (toApps) => NewAgentPage(
        host: host,
        inHome: true,
        back: toApps,
        launched: (id) {
          toApps();
          _open(id);
        },
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
    ),
  );

  /// An agent's ··· menu, from a row of the history.
  void _menu(String id) {
    final e = host.service.source.entry(id);
    if (e != null) showSessionMenu(host, e, rename: () => _open('rename:$id'));
  }
  late final AnimationController _t = AnimationController(vsync: this, duration: _push, value: 1);
  _Page? _leaving;

  SideHost get host => widget.host;

  bool get onHome => _pages.length == 1 && _leaving == null;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _open(String what) => switch (what) {
    'new' => _pushPage(_Page('new', () => NewAgentPage(host: host, back: back, launched: _launched))),
    final w when w.startsWith('rename:') => _pushPage(_Page(w, () => RenamePage(host: host, id: w.substring(7), back: back))),
    _ => _pushPage(_Page('agent:$what', () => AgentPage(host: host, id: what, back: back, rename: () => _open('rename:$what')))),
  };

  void _launched(String id) =>
      _replaceTop(_Page('agent:$id', () => AgentPage(host: host, id: id, back: back, rename: () => _open('rename:$id'))));

  void _pushPage(_Page page) {
    if (_pages.last.key == page.key) return;
    setState(() => _pages.add(page));
    widget.onHome?.call(false);
    _t.value = 0;
    _t.animateTo(1, curve: Motion.reduced(context) ? Curves.linear : _curve, duration: Motion.reduced(context) ? Duration.zero : _push);
  }

  void back() {
    if (_pages.length < 2 || _leaving != null) return;
    setState(() => _leaving = _pages.removeLast());
    if (_pages.length == 1) widget.onHome?.call(true);
    _t.animateBack(0, curve: _curve.flipped, duration: Motion.reduced(context) ? Duration.zero : _push).whenComplete(() {
      if (!mounted) return;
      setState(() => _leaving = null);
      _t.value = 1;
    });
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
    Widget page(_Page p) => KeyedSubtree(
      key: ValueKey(p.key),
      child: ColoredBox(
        color: ui.island,
        child: p.build(),
      ),
    );
    return ListenableBuilder(
      listenable: host.service,
      builder: (context, _) => AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          final moving = t < 1;
          final width = widget.layout.pageSize.width;
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
                    if (below != null)
                      moving
                          ? Transform.translate(
                              offset: Offset(-.28 * width * t, 0),
                              child: Opacity(opacity: 1 - .5 * t, child: page(below)),
                            )
                          : Offstage(child: TickerMode(enabled: false, child: page(below))),
                    Transform.translate(offset: Offset((1 - t) * width, 0), child: page(top)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// « Terminer » on an agent stopped by its limit: no relaunch, no more
/// waiting; it leaves « Travaillent » and the island, and stays as done.
void finishLimit(SideHost host, String id) {
  Enchantments.instance.cancel(id);
  host.service.source.settle(id);
}
