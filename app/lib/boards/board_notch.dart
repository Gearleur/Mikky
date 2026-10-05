import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../home/home_view.dart';
import '../home/tools_rail.dart';
import '../side/session_steps.dart';
import '../ui/app_tile.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/edge_rail.dart';
import '../ui/icons.dart';
import '../ui/page_dots.dart';
import '../ui/pixel_fx.dart';
import '../ui/side.dart';
import '../ui/sliding_hover.dart';
import '../ui/status.dart';
import '../ui/surface.dart';
import '../ui/tabs.dart';
import '../ui/tasks.dart' show TaskStepState;
import '../ui/tokens.dart';
import 'board_home.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

// The notch (user, 2026-10-05), to replace the home at the top, and the
// same idea at the right: Mikky bigger, looking at the latest task (its
// steps, its end, no messages); four other apps, wide enough for a title,
// a line that changes, and the software the task runs in — VS Code is
// VS Code; the model only when it is the Claude or Codex app itself.
// Quiet controls, no block for nothing. Prototypes: the app keeps
// `HomeView` until one is chosen.

/// Where a task runs: what its tile shows rather than the model. Read from
/// the sessions: Claude's `entrypoint` (`claude-vscode`, `cli`), Codex's
/// `originator` (`codex_vscode`, `Codex Desktop`, `codex_exec`).
enum HostApp {
  vscode('VS Code'),
  terminal('Terminal'),
  claude('Claude'),
  codex('Codex'),
  mikky('Mikky');

  const HostApp(this.label);

  final String label;
}

/// The host's sign: ours for VS Code and the terminal (their logos are not
/// ours to ship; the app could later take the installed VS Code's icon),
/// the tool's logo for its own app.
Widget hostGlyph(HostApp h, double size, MikkyUi ui) => switch (h) {
  HostApp.vscode => MikkyIcon('code', size: size, color: ui.blue, stroke: 2),
  HostApp.terminal => MikkyIcon('agents', size: size, color: ui.text2),
  HostApp.claude => BrandLogo(Brand.claude, size: size),
  HostApp.codex => BrandLogo(Brand.codex, size: size),
  HostApp.mikky => MiniMikky(size: size * 1.4, animate: false, badge: false),
};

/// One of the other apps: its task, its line that changes, where it runs.
class NotchApp {
  const NotchApp(this.title, this.line, this.host, this.status);

  final String title;
  final String line;
  final HostApp host;
  final UiStatus status;
}

const _apps = [
  NotchApp('Met à jour le site', 'Attend : npm run build', HostApp.codex, UiStatus.approval),
  NotchApp('Prépare le plan de l’API', 'Lit api.md', HostApp.vscode, UiStatus.working),
  NotchApp('Traduis la documentation', 'Limite · reprend à 17 h 10', HostApp.terminal, UiStatus.limited),
  NotchApp('Résume la spec', 'Terminée · il y a 5 min', HostApp.claude, UiStatus.finished),
];

/// The task Mikky looks at: the latest one at work.
class NotchTask {
  const NotchTask({required this.name, required this.host, required this.log});

  final String name;
  final HostApp host;
  final SessionLog log;

  AgentStatus get status => log.statusAt(log.lastEventAt ?? DateTime(2026));
}

/// How the other apps are drawn.
enum AppsStyle {
  /// Wide tiles: the sign, the title, the line, on the tile.
  cards,

  /// A small tile with the sign, the words beside it on the island.
  icons,
}

// ------------------------------------------------------------------ top

/// The notch at the top: the bar (modes, tools), Mikky and his task on
/// the left, four apps in two columns and two rows on the right, the foot.
class NotchTop extends StatelessWidget {
  const NotchTop({super.key, this.task, this.style = AppsStyle.cards});

  static const size = Size(680, 200);
  static const _content = 50.0, _taskHeight = 112.0, _mikky = 84.0;
  static const _tileW = 168.0, _tileH = 44.0, _gap = 8.0;
  static const _gridW = 2 * _tileW + _gap, _gridH = 2 * _tileH + _gap;

  final NotchTask? task;
  final AppsStyle style;

  @override
  Widget build(BuildContext context) {
    const gridLeft = 680 - 16 - _gridW;
    const taskLeft = 10 + _mikky + 2;
    return HomeFrame(
      layout: HomeLayout.top,
      size: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 10, top: _content + (_taskHeight - _mikky) / 2, child: _Watcher(task: task, size: _mikky)),
        Positioned(left: taskLeft, top: _content, width: gridLeft - taskLeft - 12, height: _taskHeight, child: _glance(task, 4)),
        Positioned(left: gridLeft, top: _content + (_taskHeight - _gridH) / 2, child: _AppsGrid(style: style, columns: 2, width: _tileW, height: _tileH, gap: _gap)),
        const Positioned(top: 10, left: 0, right: 0, child: Center(child: _Modes())),
        Positioned(top: 10, right: 0, child: ToolsRail(edge: RailEdge.right, height: _Modes.height, onPressed: () {})),
        const Positioned(left: 12, bottom: 8, child: _Mini('history', tooltip: 'Historique')),
        Positioned(left: gridLeft, width: _gridW, bottom: 8 + (24 - PageDots.height) / 2, child: Center(child: PageDots(count: 2, page: 0, onSelect: (_) {}))),
        const Positioned(right: 14, bottom: 8, child: _Environment()),
      ]),
    );
  }
}

// ---------------------------------------------------------------- right

/// The notch at the right edge, upright: the bar, Mikky and his task at
/// the top, the four apps under them, the foot.
class NotchRight extends StatelessWidget {
  const NotchRight({super.key, this.task, this.style = AppsStyle.cards, this.list = true});

  static const width = 300.0;
  static const _content = 50.0, _taskHeight = 104.0, _mikky = 72.0;

  final NotchTask? task;
  final AppsStyle style;

  /// One column of four (else two by two).
  final bool list;

  double get _appsHeight => list ? 4 * 40 + 3 * 6 : 2 * 44 + 8;
  double get height => _content + _taskHeight + 10 + _appsHeight + 12 + 24 + 8;

  @override
  Widget build(BuildContext context) {
    const taskLeft = 10 + _mikky + 2;
    const appsTop = _content + _taskHeight + 10;
    return HomeFrame(
      layout: HomeLayout.right,
      size: Size(width, height),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 10, top: _content + (_taskHeight - _mikky) / 2, child: _Watcher(task: task, size: _mikky)),
        Positioned(left: taskLeft, top: _content, width: width - taskLeft - 14, height: _taskHeight, child: _glance(task, 3)),
        Positioned(
          left: 16,
          right: 16,
          top: appsTop,
          child: list
              ? _AppsGrid(style: style, columns: 1, width: width - 32, height: 40, gap: 6)
              : _AppsGrid(style: style, columns: 2, width: (width - 32 - 8) / 2, height: 44, gap: 8),
        ),
        const Positioned(top: 10, left: 0, right: 0, child: Center(child: _Modes())),
        Positioned(top: 10, right: 0, child: ToolsRail(edge: RailEdge.right, height: _Modes.height, onPressed: () {})),
        const Positioned(left: 12, bottom: 8, child: _Mini('history', tooltip: 'Historique')),
        Positioned(left: 0, right: 0, bottom: 8 + (24 - PageDots.height) / 2, child: Center(child: PageDots(count: 2, page: 0, onSelect: (_) {}))),
        const Positioned(right: 14, bottom: 8, child: _Environment()),
      ]),
    );
  }
}

// ---------------------------------------------------------------- parts

/// Mikky, bigger, turned to the task beside him; asleep without one.
class _Watcher extends StatelessWidget {
  const _Watcher({required this.task, required this.size});

  final NotchTask? task;
  final double size;

  @override
  Widget build(BuildContext context) => MiniMikky(
    size: size,
    animate: false,
    state: task == null ? MikkyState.sleeping : mikkyStateOf(task!.status),
    badge: false,
    look: const Offset(1, .3),
  );
}

Widget _glance(NotchTask? task, int max) => task == null ? const _Nothing() : _TaskGlance(task: task, max: max);

/// The four other apps, [columns] wide.
class _AppsGrid extends StatelessWidget {
  const _AppsGrid({required this.style, required this.columns, required this.width, required this.height, required this.gap});

  final AppsStyle style;
  final int columns;
  final double width, height, gap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: columns * width + (columns - 1) * gap,
    child: Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [for (final a in _apps) style == AppsStyle.cards ? _AppCard(app: a, width: width, height: height) : _AppIcon(app: a, width: width, height: height)],
    ),
  );
}

/// The state's pastille on a tile's corner, as on [AppTile] (16 px).
Widget _pin(UiStatus status, MikkyUi ui) => Surface(
  width: 16,
  height: 16,
  color: ui.thumb,
  shadows: [...ui.shCtl, CssShadow(0, 0, 0, ui.line, spread: .7, inset: true)],
  child: Center(child: StatusFx(status, size: 10)),
);

/// The title and the line that changes.
Widget _words(NotchApp app, MikkyUi ui) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(app.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text, height: 1.25)),
    const SizedBox(height: 1),
    Text(app.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, color: ui.text3, height: 1.25)),
  ],
);

/// A wide tile: the app's face as [AppTile], with its words on it.
class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.width, required this.height});

  final NotchApp app;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Semantics(
      button: true,
      label: '${app.title}, ${app.host.label}',
      child: Stack(clipBehavior: Clip.none, children: [
        Surface(
          width: width,
          height: height,
          radius: 12,
          gradient: ui.tile,
          shadows: [...ui.shThumb, ui.highlight, CssShadow(0, 0, 0, ui.line, spread: .8, inset: true)],
          padding: const EdgeInsets.only(left: 11, right: 12),
          child: Row(children: [
            SizedBox(width: 16, child: Center(child: hostGlyph(app.host, 15, ui))),
            const SizedBox(width: 9),
            Expanded(child: _words(app, ui)),
          ]),
        ),
        Positioned(right: -4, top: -4, child: _pin(app.status, ui)),
      ]),
    );
  }
}

/// A small tile with the sign, the words beside it, on the island.
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app, required this.width, required this.height});

  final NotchApp app;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final tile = height - 4;
    return SizedBox(
      width: width,
      height: height,
      child: Row(children: [
        AppTile(size: tile, label: '${app.title}, ${app.host.label}', status: app.status, onTap: () {}, child: Center(child: hostGlyph(app.host, 15, ui))),
        const SizedBox(width: 9),
        Expanded(child: _words(app, ui)),
      ]),
    );
  }
}

/// The modes, 32 px high, icons of 15 (44 and 18 before; 26 and 13 in
/// the first trial, too small).
class _Modes extends StatelessWidget {
  const _Modes();

  static const height = 32.0;

  @override
  Widget build(BuildContext context) => MTabBar(
    mini: true,
    height: height,
    ink: true,
    selected: 0,
    onChanged: (_) {},
    items: const [TabItem('grid', label: 'Applications'), TabItem('chat', label: 'Chat')],
  );
}

/// A small control of the foot: an icon of 14, round on hover.
class _Mini extends StatelessWidget {
  const _Mini(this.icon, {required this.tooltip});

  final String icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Semantics(
      label: tooltip,
      button: true,
      child: HoverRow(onTap: () {}, padding: const EdgeInsets.all(5), child: MikkyIcon(icon, size: 14, color: ui.text3)),
    );
  }
}

/// « Local », small, with its star: the environment (a menu, as today).
class _Environment extends StatelessWidget {
  const _Environment();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return HoverRow(
      onTap: () {},
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Local', style: uiText(TextSize.small, weight: FontWeight.w500, color: ui.text2)),
        const SizedBox(width: 6),
        const PixelStar(PixelFxPalette.grey, size: 10),
      ]),
    );
  }
}

/// No task: Mikky sleeps.
class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Align(alignment: Alignment.centerLeft, child: Text('Rien en cours', style: uiText(TextSize.label, color: ui.text3)));
  }
}

/// The latest task at a glance: where it runs and its title, its state in
/// a few words, its steps (done, at work, to come). No messages, no card.
class _TaskGlance extends StatelessWidget {
  const _TaskGlance({required this.task, required this.max});

  final NotchTask task;
  final int max;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final log = task.log;
    final status = task.status;
    final steps = glanceSteps(log, max: max);
    final turn = log.turns.lastOrNull;
    final waiting = status == AgentStatus.approval || status == AgentStatus.question;
    final state = switch (status) {
      AgentStatus.approval => 'attend ton feu vert',
      AgentStatus.question => 'te pose une question',
      AgentStatus.finished => _finished(log),
      AgentStatus.rateLimited => log.detail.replaceFirst('Limite atteinte', 'limite atteinte'),
      AgentStatus.error => 'en erreur',
      AgentStatus.idle || AgentStatus.paused => 'arrêtée',
      _ => turn != null && turn.plan.isNotEmpty ? 'au travail · ${planCount(planSteps(turn))}' : 'au travail',
    };
    final stateColor = switch (status) {
      AgentStatus.approval || AgentStatus.question => ui.amber,
      AgentStatus.error => ui.red,
      AgentStatus.finished => ui.green,
      _ => ui.text3,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.label, weight: FontWeight.w600, color: ui.text)),
        const SizedBox(height: 3),
        Row(children: [
          hostGlyph(task.host, 11, ui),
          const SizedBox(width: 5),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${task.host.label} · ', style: TextStyle(color: ui.text3)),
                TextSpan(text: state, style: TextStyle(color: stateColor)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: uiText(TextSize.caption, weight: FontWeight.w500, tabular: true),
            ),
          ),
        ]),
        const SizedBox(height: 7),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              SizedBox(width: 10, child: Center(child: _star(s, ui, waiting))),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(
                    TextSize.small,
                    weight: s.state == TaskStepState.now ? FontWeight.w600 : FontWeight.w400,
                    color: switch (s.state) {
                      TaskStepState.now => ui.text,
                      TaskStepState.todo => ui.text3,
                      _ => ui.text2,
                    },
                    height: 1.25,
                  ),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  static String _finished(SessionLog log) {
    final start = log.items.firstOrNull?.at, end = log.lastEventAt;
    if (start == null || end == null) return 'terminée';
    final m = end.difference(start).inMinutes;
    return 'terminée · ${m < 1 ? 'moins d’une min' : '$m min'}';
  }

  static Widget _star(MainStep s, MikkyUi ui, bool waiting) => switch (s.state) {
    TaskStepState.now => StatusFx(waiting ? UiStatus.approval : UiStatus.working, size: 10),
    TaskStepState.failed => const PixelStar(PixelFxPalette.red, size: 9),
    TaskStepState.todo => const Opacity(opacity: .35, child: PixelStar(PixelFxPalette.grey, size: 9)),
    TaskStepState.done => PixelStar(switch (s.tone) {
      StepTone.plan || StepTone.created => PixelFxPalette.green(ui),
      StepTone.changed => PixelFxPalette.blue,
      StepTone.deleted => PixelFxPalette.red,
      StepTone.moved => PixelFxPalette.yellow,
      StepTone.ran => PixelFxPalette.fire,
      StepTone.web => PixelFxPalette.violet,
      null => PixelFxPalette.grey,
    }, size: 9),
  };
}

// --------------------------------------------------------------- boards

NotchTask _task(SessionLog log, {String name = 'Corrige les tests du moteur', HostApp host = HostApp.vscode}) => NotchTask(name: name, host: host, log: log);

/// Before and after: the controls of the bar and the foot.
class _Sizes extends StatelessWidget {
  const _Sizes({required this.small});

  final bool small;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final h = small ? _Modes.height : 44.0;
    return BoardPane(
      width: 300,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          MTabBar(mini: true, height: h, ink: true, selected: 0, onChanged: (_) {}, items: const [TabItem('grid', label: 'Applications'), TabItem('chat', label: 'Chat')]),
          const Spacer(),
          ToolsRail(edge: RailEdge.right, height: h, onPressed: () {}),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          if (small) const _Mini('history', tooltip: 'Historique') else RoundButton('history', size: 34, onPressed: () {}),
          const Spacer(),
          if (small) const _Environment() else Text('Local  (36 px)', style: uiText(TextSize.label, weight: FontWeight.w600, color: ui.text)),
        ]),
      ]),
    );
  }
}

final notchTopBoard = BoardSpec('Notch Top', 'L’accueil du haut à venir : Mikky regarde la dernière tâche, quatre applications', (context) => [
  BoardSection(
    title: 'Notch Top',
    note: '680 × 200, à la place de l’accueil du haut. À gauche, Mikky (84) tourné vers la dernière tâche au travail : son titre, où elle tourne et son état, ses étapes (faites, en cours, à venir), sans les messages. À droite, quatre applications en 2 × 2, assez larges pour un titre, une ligne qui change et le logiciel où elles tournent (VS Code, Terminal, l’app Claude ou Codex) plutôt que le modèle. Modes et outils à 32 px, historique et environnement en petit. Plus tard : Ctrl + clic ouvre l’agent dans son logiciel.',
    frames: [
      BoardFrame(label: 'Tuiles larges', note: 'Le signe, le titre et la ligne sur la tuile.', width: 680, child: NotchTop(task: _task(FakeSessions.working()))),
      BoardFrame(label: 'Icônes et mots', note: 'Une petite tuile avec le signe, les mots à côté, sans fond.', width: 680, child: NotchTop(task: _task(FakeSessions.working()), style: AppsStyle.icons)),
    ],
  ),
  BoardSection(
    title: 'La tâche que Mikky regarde',
    note: 'Seulement les étapes qui apparaissent, et la fin. Où elle tourne avant son état : VS Code, Terminal, Claude, Codex, Mikky.',
    frames: [
      BoardFrame(label: 'Au travail, avec un plan', width: 680, child: NotchTop(task: _task(FakeSessions.working()))),
      BoardFrame(label: 'Au travail, sans plan', width: 680, child: NotchTop(task: _task(FakeSessions.workingNoPlan(), name: 'Ajoute un test Codex', host: HostApp.terminal))),
      BoardFrame(label: 'Attend ton feu vert', width: 680, child: NotchTop(task: _task(FakeSessions.approval(), name: 'Met à jour le site', host: HostApp.codex))),
      BoardFrame(label: 'Terminée', width: 680, child: NotchTop(task: _task(FakeSessions.done(), host: HostApp.mikky))),
      BoardFrame(label: 'Limite atteinte', width: 680, child: NotchTop(task: _task(FakeSessions.limited(), host: HostApp.claude))),
      const BoardFrame(label: 'Rien en cours', note: 'Mikky dort.', width: 680, child: NotchTop()),
    ],
  ),
  const BoardSection(
    title: 'Tailles',
    note: 'Les commandes d’aujourd’hui et celles du notch (32 px).',
    frames: [
      BoardFrame(label: 'Avant', child: _Sizes(small: false)),
      BoardFrame(label: 'Après', child: _Sizes(small: true)),
    ],
  ),
]);

final notchRightBoard = BoardSpec('Notch Right', 'L’accueil de droite à venir : la même idée, debout', (context) => [
  BoardSection(
    title: 'Notch Right',
    note: '300 de large, collé au bord droit. En haut, Mikky (72) et la tâche qu’il regarde (trois étapes) ; en dessous, les quatre autres applications ; le pied en petit.',
    frames: [
      BoardFrame(label: 'Liste · tuiles larges', note: 'Une colonne de quatre : les titres en entier.', width: 300, child: NotchRight(task: _task(FakeSessions.working()))),
      BoardFrame(label: 'Liste · icônes et mots', width: 300, child: NotchRight(task: _task(FakeSessions.working()), style: AppsStyle.icons)),
      BoardFrame(label: '2 × 2 · tuiles larges', note: 'Plus court, les titres coupés plus tôt.', width: 300, child: NotchRight(task: _task(FakeSessions.working()), list: false)),
    ],
  ),
  BoardSection(
    title: 'La tâche que Mikky regarde',
    frames: [
      BoardFrame(label: 'Attend ton feu vert', width: 300, child: NotchRight(task: _task(FakeSessions.approval(), name: 'Met à jour le site', host: HostApp.codex))),
      BoardFrame(label: 'Terminée', width: 300, child: NotchRight(task: _task(FakeSessions.done(), host: HostApp.mikky))),
      const BoardFrame(label: 'Rien en cours', width: 300, child: NotchRight()),
    ],
  ),
]);
