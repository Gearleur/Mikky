import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/agents_service.dart';
import '../overlay/overlay_channel.dart';
import '../ui/buttons.dart';
import '../ui/cards.dart';
import '../ui/feedback.dart';
import '../ui/motion.dart';
import '../ui/side.dart';
import '../ui/tokens.dart';
import 'agent_page.dart';
import 'new_agent_page.dart';
import 'session_views.dart';

/// What the small window needs from the island around it.
class SideHost {
  const SideHost({
    required this.service,
    required this.answer,
    required this.pickFolder,
    required this.showMenu,
    required this.islandMenu,
  });

  final AgentsService service;

  /// Oui / Non to agent [id] (the island makes Mikky react).
  final void Function(String id, bool allow) answer;
  final Future<String?> Function(String title) pickFolder;
  final Future<int?> Function(List<MenuEntry> entries) showMenu;

  /// The island's own menu (theme, position, quit…).
  final VoidCallback islandMenu;
}

/// The small window at the right edge (UX `ux-a.html`): the agents home,
/// an agent's page (Suivi / Chat), the new agent. Pages are stacked; a new
/// one slides in from the right (380 ms), the one below moves 28 % left
/// and dims.
class SideApp extends StatefulWidget {
  const SideApp({super.key, required this.host, this.onHome});

  final SideHost host;

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

  late final List<_Page> _pages = [_Page('home', () => HomePage(host: widget.host, open: _open))];
  late final AnimationController _t = AnimationController(vsync: this, duration: _push, value: 1);
  _Page? _leaving;

  /// Which home groups are unfolded; kept while the window is closed.
  final Map<HomeGroup, bool> _groups = {HomeGroup.waiting: true, HomeGroup.working: true, HomeGroup.done: true, HomeGroup.history: false};

  SideHost get host => widget.host;

  bool get onHome => _pages.length == 1 && _leaving == null;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _open(String what) => switch (what) {
        'new' => _pushPage(_Page('new', () => NewAgentPage(host: host, back: back, launched: _launched))),
        _ => _pushPage(_Page('agent:$what', () => AgentPage(host: host, id: what, back: back))),
      };

  void _launched(String id) => _replaceTop(_Page('agent:$id', () => AgentPage(host: host, id: id, back: back)));

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

  /// The new agent becomes its agent page (a short fade, no slide).
  void _replaceTop(_Page page) => setState(() => _pages[_pages.length - 1] = page);

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final top = _leaving ?? _pages.last;
    final below = _leaving != null ? _pages.last : (_pages.length > 1 ? _pages[_pages.length - 2] : null);
    Widget page(_Page p) => KeyedSubtree(
          key: ValueKey(p.key),
          child: ColoredBox(color: ui.island, child: _GroupsScope(groups: _groups, onToggle: _toggle, child: p.build())),
        );
    return ListenableBuilder(
      listenable: host.service,
      builder: (context, _) => AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          final moving = t < 1;
          return Stack(fit: StackFit.expand, clipBehavior: Clip.hardEdge, children: [
            // Pages further down keep their state but are not drawn.
            for (final p in _pages)
              if (p != top && p != below) Offstage(child: TickerMode(enabled: false, child: page(p))),
            if (below != null)
              moving
                  ? Transform.translate(offset: Offset(-.28 * 320 * t, 0), child: Opacity(opacity: 1 - .5 * t, child: page(below)))
                  : Offstage(child: TickerMode(enabled: false, child: page(below))),
            Transform.translate(offset: Offset((1 - t) * 320, 0), child: page(top)),
          ]);
        },
      ),
    );
  }

  void _toggle(HomeGroup g) => setState(() => _groups[g] = !(_groups[g] ?? true));
}

/// Gives the home its folded groups (kept by [SideAppState]).
class _GroupsScope extends InheritedWidget {
  const _GroupsScope({required this.groups, required this.onToggle, required super.child});

  final Map<HomeGroup, bool> groups;
  final ValueChanged<HomeGroup> onToggle;

  static _GroupsScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_GroupsScope>()!;

  @override
  bool updateShouldNotify(_GroupsScope old) => true;
}

/// The home: agents in groups — En attente, Travaillent, Terminés,
/// Historique (folded) — and the round arrow for a new agent.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.host, required this.open});

  final SideHost host;
  final ValueChanged<String> open;

  /// More than this in « Terminés » go to the history.
  static const maxDone = 5;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final scope = _GroupsScope.of(context);
    final now = DateTime.now();
    final groups = groupHome(host.service.source.entries, status: (e) => e.status, lastActivity: (e) => e.lastActivity, now: now);
    final done = groups[HomeGroup.done]!;
    if (done.length > maxDone) {
      groups[HomeGroup.history]!.insertAll(0, done.sublist(maxDone));
      done.removeRange(maxDone, done.length);
    }
    final labels = {
      HomeGroup.waiting: ('En attente', ui.amber),
      HomeGroup.working: ('Travaillent', ui.blue),
      HomeGroup.done: ('Terminés', ui.green),
      HomeGroup.history: ('Historique', ui.grey),
    };
    final body = <Widget>[];
    for (final g in HomeGroup.values) {
      final list = groups[g]!;
      if (list.isEmpty) continue;
      final (label, color) = labels[g]!;
      final isOpen = scope.groups[g] ?? true;
      body.add(GroupHeader(label: label, color: color, count: list.length, open: isOpen, first: body.isEmpty, onTap: () => scope.onToggle(g)));
      body.add(AnimatedSize(
        duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 280),
        curve: Motion.enter,
        alignment: Alignment.topCenter,
        child: isOpen
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < list.length; i++)
                  Padding(padding: EdgeInsets.only(top: i == 0 || g == HomeGroup.history ? 0 : 8), child: _card(context, list[i], g, now)),
              ])
            : const SizedBox(width: double.infinity),
      ));
    }
    return Stack(children: [
      SideHead(
        title: 'Agents',
        // The island draws Mikky here (it moves from the tab to this spot).
        leading: const SizedBox(width: 42, height: 40),
        actions: [RoundButton('more', size: 34, onPressed: host.islandMenu, tooltip: 'Plus')],
      ),
      Positioned.fill(
        top: 68,
        child: body.isEmpty
            ? const _Empty()
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 72),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
              ),
      ),
      Positioned(right: 16, bottom: 16, child: RoundButton('go', size: 46, ink: true, onPressed: () => open('new'), tooltip: 'Nouvel agent')),
    ]);
  }

  Widget _card(BuildContext context, AgentEntry e, HomeGroup g, DateTime now) {
    final log = e.log;
    final external = e.origin == AgentOrigin.external;
    final where = external ? ' · hors de Mikky' : '';
    return switch (g) {
      HomeGroup.waiting when e.status == AgentStatus.approval || e.status == AgentStatus.question => AgentCard(
          status: UiStatus.approval,
          title: e.name,
          who: whoOf(e),
          subtitle: askLabel(log),
          style: AgentCardStyle.waiting,
          onTap: () => open(e.id),
          actions: e.live
              ? WaitActions(command: log.detail, onYes: () => host.answer(e.id, true), onNo: () => host.answer(e.id, false))
              : null,
        ),
      HomeGroup.waiting => AgentCard(
          status: UiStatus.of(e.status),
          title: e.name,
          who: whoOf(e),
          subtitle: log.detail.isEmpty ? 'Erreur' : log.detail,
          onTap: () => open(e.id),
        ),
      HomeGroup.working => AgentCard(
          status: UiStatus.of(e.status),
          title: e.name,
          who: whoOf(e),
          subtitle: '${log.detail.isEmpty ? 'Réfléchit…' : log.detail}$where',
          onTap: () => open(e.id),
        ),
      HomeGroup.done => AgentCard(
          status: UiStatus.of(e.status),
          title: e.name,
          who: whoOf(e),
          subtitle: '${_capitalized(ago(e.lastActivity, now))}$where',
          style: AgentCardStyle.done,
          onTap: () => open(e.id),
        ),
      HomeGroup.history => AgentCard(
          status: UiStatus.of(e.status),
          title: e.name,
          who: whoOf(e),
          style: AgentCardStyle.old,
          onTap: () => open(e.id),
        ),
    };
  }

  static String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 120, 32, 0),
      child: Column(children: [
        Text('Aucun agent pour l’instant', textAlign: TextAlign.center, style: uiText(14, weight: FontWeight.w500, color: ui.text2)),
        const SizedBox(height: 6),
        Text('La flèche en bas lance Claude ou Codex.', textAlign: TextAlign.center, style: uiText(12.5, color: ui.text3)),
      ]),
    );
  }
}
