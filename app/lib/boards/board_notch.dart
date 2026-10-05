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
// steps, its end, no messages); the other apps wide enough for a title,
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
  NotchApp('Corrige les tests du moteur', 'Terminée · il y a 12 min', HostApp.vscode, UiStatus.finished),
  NotchApp('Nettoie les imports', 'Terminée · hier', HostApp.mikky, UiStatus.finished),
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

/// How far the task is, next to its state: its plan's steps.
enum ProgressStyle {
  /// One small segment per step.
  segments,

  /// A thin bar.
  bar,
}

// ------------------------------------------------------------------ top

/// Where the parts of the top notch go.
enum TopLayout {
  /// The bar over everything; Mikky and his task on the left (the
  /// software over the title), the apps on the right.
  side,

  /// As [side], the software's sign and name in the middle of the left
  /// part, on the bar's line.
  centered,

  /// Really in two (user, 2026-10-05): the left part takes the whole
  /// height for Mikky and his task; the right part has its own controls —
  /// the modes in its middle, the history at its bottom left.
  split,
}

/// The notch at the top: Mikky and his task on the left, four apps in two
/// columns and two rows on the right, with arrows when there are more;
/// the modes, the tools, the history, the pages, the environment. Nothing
/// at work: a third column of apps takes the task's place.
class NotchTop extends StatelessWidget {
  const NotchTop({super.key, this.task, this.layout = TopLayout.side, this.progress = ProgressStyle.segments, this.page = 0});

  static const _content = 50.0, _taskHeight = 128.0, _tileH = 44.0, _gap = 8.0, _arrow = 22.0;
  static const _gridH = 2 * _tileH + _gap;

  final NotchTask? task;
  final TopLayout layout;
  final ProgressStyle progress;

  /// The page of apps shown (two pages on the boards).
  final int page;

  bool get _split => layout == TopLayout.split;
  Size get size => _split ? const Size(744, 216) : const Size(730, 216);

  @override
  Widget build(BuildContext context) {
    final t = task;
    final w = size.width;
    final tileW = _split ? 160.0 : 168.0;
    final columns = t == null ? 3 : 2;
    final gridW = columns * tileW + (columns - 1) * _gap;
    // The right part: from the divide (split), else from the left arrow.
    // Nothing at work: Mikky alone on the left, the divide moves for the
    // third column.
    final rightLeft = _split ? (t == null ? 150.0 : 344.0) : w - 40 - gridW - 30;
    final gridLeft = _split ? rightLeft + (w - rightLeft - gridW) / 2 : w - 40 - gridW;
    final gridTop = _split ? 52.0 : _content + (_taskHeight - _gridH) / 2;
    final mikky = _split ? 96.0 : 84.0;
    final arrowTop = gridTop + _gridH / 2 - _arrow / 2;
    final left = <Widget>[
      if (_split) ...[
        Positioned(left: 14, top: (size.height - mikky) / 2 - 4, child: _Watcher(task: t, size: mikky)),
        if (t != null)
          Positioned(left: 14 + mikky + 4, top: 16, width: rightLeft - 14 - mikky - 4 - 16, bottom: 16, child: _TaskGlance(task: t, max: 4, progress: progress)),
        // The divide, a hairline.
        Positioned(left: rightLeft, top: 18, bottom: 18, child: const _Divide()),
      ] else ...[
        Positioned(left: 10, top: _content + (_taskHeight - mikky) / 2, child: _Watcher(task: t, size: mikky)),
        if (t != null)
          Positioned(
            left: 10 + mikky + 2,
            top: _content,
            width: rightLeft - 10 - mikky - 2,
            height: _taskHeight,
            child: _TaskGlance(task: t, max: 3, progress: progress, host: layout == TopLayout.side),
          ),
        if (t != null && layout == TopLayout.centered)
          Positioned(left: 0, width: rightLeft, top: 10, height: _Modes.height, child: Center(child: _HostLine(host: t.host))),
      ],
    ];
    return HomeFrame(
      layout: HomeLayout.top,
      size: size,
      child: Stack(clipBehavior: Clip.none, children: [
        ...left,
        Positioned(
          left: gridLeft,
          top: gridTop,
          child: _AppsGrid(style: AppsStyle.cards, columns: columns, count: columns * 2, skip: page * columns * 2, width: tileW, height: _tileH, gap: _gap),
        ),
        // More apps: the arrows on each side of them.
        if (page > 0) Positioned(left: gridLeft - _arrow - 8, top: arrowTop, child: const _Arrow(next: false)),
        if (page == 0) Positioned(left: gridLeft + gridW + 8, top: arrowTop, child: const _Arrow(next: true)),
        if (_split)
          Positioned(top: 10, left: rightLeft, right: 0, child: const Center(child: _Modes()))
        else if (layout == TopLayout.centered)
          Positioned(top: 10, left: rightLeft, width: gridW + 60, child: const Center(child: _Modes()))
        else
          const Positioned(top: 10, left: 0, right: 0, child: Center(child: _Modes())),
        Positioned(top: 10, right: 0, child: ToolsRail(edge: RailEdge.right, height: _Modes.height, onPressed: () {})),
        Positioned(left: _split ? rightLeft + 10 : 12, bottom: 8, child: const _Mini('history', tooltip: 'Historique')),
        Positioned(left: gridLeft, width: gridW, bottom: 8 + (24 - PageDots.height) / 2, child: Center(child: PageDots(count: 2, page: page, onSelect: (_) {}))),
        const Positioned(right: 14, bottom: 8, child: _Environment()),
      ]),
    );
  }
}

/// A page arrow by the apps, small.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.next});

  final bool next;

  @override
  Widget build(BuildContext context) =>
      RoundButton(next ? 'right' : 'left', size: NotchTop._arrow, tooltip: next ? 'Applications suivantes' : 'Applications précédentes', onPressed: () {});
}

/// The hairline between the two parts.
class _Divide extends StatelessWidget {
  const _Divide();

  @override
  Widget build(BuildContext context) => Container(width: 1, color: MikkyUi.of(context).line);
}

/// The software a task runs in: its sign and its name.
class _HostLine extends StatelessWidget {
  const _HostLine({required this.host});

  final HostApp host;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      hostGlyph(host, 14, ui),
      const SizedBox(width: 6),
      Text(host.label, style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text2)),
    ]);
  }
}

// ---------------------------------------------------------------- right

/// Trials for the right edge (the first, Mikky beside his task over a
/// list, did not convince).
enum RightStyle {
  /// Mikky in the middle at the top, his task centered under him (no
  /// steps), the apps in a list.
  center,

  /// Mikky small beside the software and the title, the steps under them
  /// across the width, the apps two by two as icons and words.
  header,

  /// Mikky beside his task, the apps in a row of small tiles, as a dock.
  dock,
}

/// The notch at the right edge, upright, 300 wide.
class NotchRight extends StatelessWidget {
  const NotchRight({super.key, this.task, this.style = RightStyle.center});

  static const width = 300.0;
  static const _content = 50.0;

  final NotchTask? task;
  final RightStyle style;

  /// The top part (Mikky and his task), then the apps.
  (double, double) get _parts => switch (style) {
    RightStyle.center => (136.0, 4 * 40.0 + 3 * 6),
    RightStyle.header => (132.0, 2 * 44.0 + 10),
    RightStyle.dock => (128.0, 44.0),
  };

  double get height => _content + _parts.$1 + 12 + _parts.$2 + 12 + 24 + 8;

  @override
  Widget build(BuildContext context) {
    final (top, _) = _parts;
    final appsTop = _content + top + 12;
    final t = task;
    final head = switch (style) {
      RightStyle.center => [
        Positioned(left: 0, right: 0, top: _content - 6, child: Center(child: _Watcher(task: t, size: 76, look: const Offset(0, .7)))),
        Positioned(
          left: 20,
          right: 20,
          top: _content + 74,
          child: t == null ? const _Nothing(center: true) : _TaskGlance(task: t, max: 0, center: true),
        ),
      ],
      RightStyle.header => [
        Positioned(left: 10, top: _content - 4, child: _Watcher(task: t, size: 60)),
        Positioned(left: 74, right: 14, top: _content, height: 62, child: t == null ? const _Nothing() : _TaskGlance(task: t, max: 0)),
        if (t != null) Positioned(left: 14, right: 14, top: _content + 72, child: _TaskSteps(task: t, max: 3)),
      ],
      RightStyle.dock => [
        Positioned(left: 10, top: _content + (top - 72) / 2, child: _Watcher(task: t, size: 72)),
        Positioned(left: 84, right: 14, top: _content, height: top, child: t == null ? const _Nothing() : _TaskGlance(task: t, max: 3)),
      ],
    };
    const appsW = width - 32;
    final apps = switch (style) {
      RightStyle.center => const _AppsGrid(style: AppsStyle.cards, columns: 1, width: appsW, height: 40, gap: 6),
      RightStyle.header => const _AppsGrid(style: AppsStyle.icons, columns: 2, width: (appsW - 10) / 2, height: 44, gap: 10),
      RightStyle.dock => const _Dock(),
    };
    return HomeFrame(
      layout: HomeLayout.right,
      size: Size(width, height),
      child: Stack(clipBehavior: Clip.none, children: [
        ...head,
        Positioned(left: 16, right: 16, top: appsTop, child: apps),
        const Positioned(top: 10, left: 0, right: 0, child: Center(child: _Modes())),
        Positioned(top: 10, right: 0, child: ToolsRail(edge: RailEdge.right, height: _Modes.height, onPressed: () {})),
        const Positioned(left: 12, bottom: 8, child: _Mini('history', tooltip: 'Historique')),
        Positioned(left: 0, right: 0, bottom: 8 + (24 - PageDots.height) / 2, child: Center(child: PageDots(count: 2, page: 0, onSelect: (_) {}))),
        const Positioned(right: 14, bottom: 8, child: _Environment()),
      ]),
    );
  }
}

/// The apps as a dock: small tiles with their sign, the words on hover;
/// « + » at the end.
class _Dock extends StatelessWidget {
  const _Dock();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      for (final a in _apps.take(4))
        AppTile(size: 44, label: '${a.title}, ${a.host.label}', status: a.status, onTap: () {}, child: Center(child: hostGlyph(a.host, 16, ui))),
      AddTile(size: 44, onTap: () {}),
    ]);
  }
}

// ---------------------------------------------------------------- parts

/// Mikky, bigger, turned to the task beside him; asleep without one.
class _Watcher extends StatelessWidget {
  const _Watcher({required this.task, required this.size, this.look = const Offset(1, .3)});

  final NotchTask? task;
  final double size;

  /// Where the task is: beside him, or under him.
  final Offset look;

  @override
  Widget build(BuildContext context) => MiniMikky(
    size: size,
    animate: false,
    state: task == null ? MikkyState.sleeping : mikkyStateOf(task!.status),
    badge: false,
    look: look,
  );
}

/// The other apps, [columns] wide: the first [count].
class _AppsGrid extends StatelessWidget {
  const _AppsGrid({required this.style, required this.columns, required this.width, required this.height, required this.gap, this.count = 4, this.skip = 0});

  final AppsStyle style;
  final int columns, count, skip;
  final double width, height, gap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: columns * width + (columns - 1) * gap,
    child: Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final a in _apps.skip(skip).take(count)) style == AppsStyle.cards ? _AppCard(app: a, width: width, height: height) : _AppIcon(app: a, width: width, height: height),
      ],
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
  const _Nothing({this.center = false});

  final bool center;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Align(
      alignment: center ? Alignment.topCenter : Alignment.centerLeft,
      child: Text('Rien en cours', style: uiText(TextSize.label, color: ui.text3)),
    );
  }
}

/// The task's state in a few words, and its color.
(String, Color) _stateOf(NotchTask task, MikkyUi ui) {
  final log = task.log;
  final turn = log.turns.lastOrNull;
  return switch (task.status) {
    AgentStatus.approval => ('Attend ton feu vert', ui.amber),
    AgentStatus.question => ('Te pose une question', ui.amber),
    AgentStatus.finished => (_finished(log), ui.green),
    AgentStatus.rateLimited => (log.detail, ui.text3),
    AgentStatus.error => ('En erreur', ui.red),
    AgentStatus.idle || AgentStatus.paused => ('Arrêtée', ui.text3),
    _ => (turn != null && turn.plan.isNotEmpty ? 'Au travail · ${planCount(planSteps(turn))}' : 'Au travail', ui.text3),
  };
}

String _finished(SessionLog log) {
  final start = log.items.firstOrNull?.at, end = log.lastEventAt;
  if (start == null || end == null) return 'Terminée';
  final m = end.difference(start).inMinutes;
  return 'Terminée · ${m < 1 ? 'moins d’une min' : '$m min'}';
}

/// How far the latest task with work is in its plan: (steps done, steps);
/// null without a plan.
(int, int)? _progressOf(SessionLog log) {
  final worked = log.turns.where((t) => t.plan.isNotEmpty || turnItems(log, t).any((i) => i is ToolItem)).lastOrNull;
  if (worked == null || worked.plan.isEmpty) return null;
  final plan = planSteps(worked);
  return (plan.where((s) => s.state == TaskStepState.done).length, plan.length);
}

/// How far the task is: a segment per step, or a thin bar.
class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total, required this.color, required this.style});

  final int done, total;
  final Color color;
  final ProgressStyle style;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    if (style == ProgressStyle.bar) {
      return Container(
        width: 56,
        height: 3,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: ui.track, borderRadius: BorderRadius.circular(1.5)),
        child: FractionallySizedBox(
          widthFactor: total == 0 ? 0 : done / total,
          heightFactor: 1,
          child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.5))),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < total; i++)
        Container(
          width: 10,
          height: 3,
          margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
          decoration: BoxDecoration(
            // Done, the one at work paler, then the ones to come.
            color: i < done ? color : (i == done ? color.withValues(alpha: .4) : ui.track),
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
    ]);
  }
}

/// The latest task at a glance (user, 2026-10-05): the software it runs
/// in, its sign and name a little bigger; its title; its state small and
/// grey with how far it is; its steps under it, a little indented. No
/// messages, no card. [max] 0: no steps.
class _TaskGlance extends StatelessWidget {
  const _TaskGlance({required this.task, required this.max, this.progress = ProgressStyle.segments, this.center = false, this.host = true});

  final NotchTask task;
  final int max;
  final ProgressStyle progress;
  final bool center;

  /// The software over the title (else shown elsewhere).
  final bool host;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final (state, stateColor) = _stateOf(task, ui);
    final p = _progressOf(task.log);
    final barColor = switch (task.status) {
      AgentStatus.finished => ui.green,
      AgentStatus.approval || AgentStatus.question => ui.amber,
      AgentStatus.rateLimited => ui.yellow,
      AgentStatus.error => ui.red,
      _ => ui.blue,
    };
    final rowSize = center ? MainAxisSize.min : MainAxisSize.max;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (host) ...[
          _HostLine(host: task.host),
          const SizedBox(height: 4),
        ],
        Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.label, weight: FontWeight.w600, color: ui.text)),
        const SizedBox(height: 3),
        Row(mainAxisSize: rowSize, children: [
          Flexible(
            child: Text(state, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, weight: FontWeight.w500, color: stateColor, tabular: true)),
          ),
          if (p != null) ...[
            const SizedBox(width: 8),
            _Progress(done: p.$1, total: p.$2, color: barColor, style: progress),
          ],
        ]),
        if (max > 0) ...[
          const SizedBox(height: 7),
          _TaskSteps(task: task, max: max),
        ],
      ],
    );
  }
}

/// The task's steps, a little indented: done, at work, to come.
class _TaskSteps extends StatelessWidget {
  const _TaskSteps({required this.task, required this.max});

  final NotchTask task;
  final int max;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final waiting = task.status == AgentStatus.approval || task.status == AgentStatus.question;
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        for (final s in glanceSteps(task.log, max: max))
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
      ]),
    );
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
    note: 'À la place de l’accueil du haut ; tuiles larges retenues. À gauche, Mikky tourné vers la dernière tâche au travail : le logiciel où elle tourne, son titre, son état en petit et gris avec sa progression, ses étapes un peu en retrait, sans les messages. À droite, quatre applications en 2 × 2 (titre, ligne qui change, logiciel), les flèches de page de chaque côté quand il y en a d’autres. Modes, outils, historique, pages, environnement. Plus tard : Ctrl + clic ouvre l’agent dans son logiciel.',
    frames: [
      BoardFrame(label: 'Côte à côte', note: '730 × 216. La barre au-dessus de tout ; le logiciel sur le titre.', width: 730, child: NotchTop(task: _task(FakeSessions.working()))),
      BoardFrame(
        label: 'Logiciel au centre',
        note: '730 × 216. Le signe et le nom du logiciel au milieu de la partie de Mikky, sur la ligne de la barre ; les modes au-dessus des applications.',
        width: 730,
        child: NotchTop(task: _task(FakeSessions.working()), layout: TopLayout.centered),
      ),
      BoardFrame(
        label: 'Divisé en deux',
        note: '744 × 216. À gauche, Mikky (96) et sa tâche sur toute la hauteur, quatre étapes ; un trait fin ; à droite ses commandes : les modes au milieu, l’historique en bas à gauche.',
        width: 744,
        child: NotchTop(task: _task(FakeSessions.working()), layout: TopLayout.split),
      ),
    ],
  ),
  BoardSection(
    title: 'Pages et rien en cours',
    note: 'Deuxième page : la flèche de gauche revient. Rien en cours : Mikky dort, une troisième colonne d’applications.',
    frames: [
      BoardFrame(label: 'Côte à côte · page 2', width: 730, child: NotchTop(task: _task(FakeSessions.working()), page: 1)),
      BoardFrame(label: 'Divisé · page 2', width: 744, child: NotchTop(task: _task(FakeSessions.working()), layout: TopLayout.split, page: 1)),
      const BoardFrame(label: 'Côte à côte · rien en cours', width: 730, child: NotchTop()),
      const BoardFrame(label: 'Divisé · rien en cours', width: 744, child: NotchTop(layout: TopLayout.split)),
    ],
  ),
  BoardSection(
    title: 'La tâche que Mikky regarde',
    note: 'Seulement les étapes qui apparaissent, et la fin. Progression : un segment par étape du plan (ou une barre fine, dernier cadre) ; sans plan, rien.',
    frames: [
      BoardFrame(label: 'Au travail, sans plan', width: 730, child: NotchTop(task: _task(FakeSessions.workingNoPlan(), name: 'Ajoute un test Codex', host: HostApp.terminal))),
      BoardFrame(label: 'Attend ton feu vert', width: 730, child: NotchTop(task: _task(FakeSessions.approval(), name: 'Met à jour le site', host: HostApp.codex))),
      BoardFrame(label: 'Terminée', width: 730, child: NotchTop(task: _task(FakeSessions.done(), host: HostApp.mikky))),
      BoardFrame(label: 'Limite atteinte', width: 730, child: NotchTop(task: _task(FakeSessions.limited(), host: HostApp.claude))),
      BoardFrame(label: 'Progression en barre', width: 730, child: NotchTop(task: _task(FakeSessions.working()), progress: ProgressStyle.bar)),
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

final notchRightBoard = BoardSpec('Notch Right', 'L’accueil de droite à venir : d’autres essais', (context) => [
  BoardSection(
    title: 'Notch Right',
    note: '300 de large, collé au bord droit. Trois idées, après la première (Mikky à côté de sa tâche, au-dessus d’une liste) qui ne convainquait pas.',
    frames: [
      BoardFrame(
        label: 'Au centre',
        note: 'Mikky au milieu en haut, le regard vers sa tâche dessous : logiciel, titre, état ; pas d’étapes. Les applications en liste.',
        width: 300,
        child: NotchRight(task: _task(FakeSessions.working())),
      ),
      BoardFrame(
        label: 'En-tête',
        note: 'Mikky petit à côté du logiciel et du titre, les étapes dessous sur toute la largeur ; les applications 2 × 2 en icônes et mots.',
        width: 300,
        child: NotchRight(task: _task(FakeSessions.working()), style: RightStyle.header),
      ),
      BoardFrame(
        label: 'Dock',
        note: 'Mikky à côté de sa tâche ; les applications en une rangée de petites tuiles, comme un dock (les mots au survol). Le plus court.',
        width: 300,
        child: NotchRight(task: _task(FakeSessions.working()), style: RightStyle.dock),
      ),
    ],
  ),
  BoardSection(
    title: 'Attend ton feu vert',
    frames: [
      for (final (label, style) in [('Au centre', RightStyle.center), ('En-tête', RightStyle.header), ('Dock', RightStyle.dock)])
        BoardFrame(label: label, width: 300, child: NotchRight(task: _task(FakeSessions.approval(), name: 'Met à jour le site', host: HostApp.codex), style: style)),
    ],
  ),
]);
