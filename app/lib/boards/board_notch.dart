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
import '../ui/tabs.dart';
import '../ui/tasks.dart' show TaskStepState;
import '../ui/tokens.dart';
import 'board_home.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

// Trials of the top notch (user, 2026-10-05): wider, Mikky bigger on the
// left looking at the latest task beside him, the other apps on the right
// in three columns and two rows, everything smaller and quieter (« plus
// premium », not made to be clicked much), no block for nothing.
// Prototypes only: the app keeps `HomeView` until one is chosen.

/// The measures of one trial.
class NotchTry {
  const NotchTry({required this.size, this.bar = true, this.tile = 46, this.gap = 12, this.rowGap = 10, this.mikky = 80, this.steps = 4});

  /// Thin bar on top: the modes and the tools, 26 px high (44 before).
  static const thin = NotchTry(size: Size(580, 188));

  /// No bar: the modes in the foot, tiny; the « + » tile starts a task.
  static const bare = NotchTry(size: Size(580, 160), bar: false);

  /// Wider, Mikky bigger, five steps.
  static const wide = NotchTry(size: Size(640, 212), tile: 52, mikky: 96, steps: 5);

  final Size size;
  final bool bar;
  final double tile, gap, rowGap, mikky;

  /// Steps of the task shown at most.
  final int steps;

  double get gridWidth => 3 * tile + 2 * gap;
  double get gridHeight => 2 * tile + rowGap;
  double get contentTop => bar ? 44 : 16;
}

/// The task Mikky looks at: the latest one at work (else the latest one).
class NotchTask {
  const NotchTask({required this.name, required this.brand, required this.log});

  final String name;
  final Brand brand;
  final SessionLog log;

  AgentStatus get status => log.statusAt(log.lastEventAt ?? DateTime(2026));
}

/// A notch's home, on a board.
class NotchHome extends StatelessWidget {
  const NotchHome({super.key, required this.spec, this.task, this.apps = const [], this.pages = 2});

  final NotchTry spec;
  final NotchTask? task;

  /// The other apps (not the one Mikky looks at).
  final List<HomeApp> apps;
  final int pages;

  @override
  Widget build(BuildContext context) {
    final s = spec, w = s.size.width;
    final top = s.contentTop;
    final taskLeft = 10 + s.mikky + 4;
    final gridLeft = w - 18 - s.gridWidth;
    final state = task == null ? MikkyState.sleeping : mikkyStateOf(task!.status);
    return HomeFrame(
      layout: HomeLayout.top,
      size: s.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Mikky, bigger, turned to the task beside him.
          Positioned(
            left: 10,
            top: top + (s.gridHeight - s.mikky) / 2 - 2,
            child: MiniMikky(size: s.mikky, animate: false, state: state, badge: false, look: const Offset(1, .3)),
          ),
          Positioned(
            left: taskLeft,
            top: top,
            width: gridLeft - taskLeft - 24,
            height: s.size.height - 30 - top,
            child: task == null ? const _Nothing() : _TaskGlance(task: task!, max: s.steps),
          ),
          Positioned(left: gridLeft, top: top, child: _grid()),
          if (s.bar) ...[
            const Positioned(top: 10, left: 0, right: 0, child: Center(child: _Modes())),
            Positioned(top: 10, right: 0, child: ToolsRail(edge: RailEdge.right, height: 26, onPressed: () {})),
          ],
          // The foot, small: history (and the modes without a bar) on the
          // left, the pages under the apps, the environment on the right.
          Positioned(
            left: 12,
            bottom: 8,
            child: Row(children: [
              if (!s.bar) ...[
                const _Mini('grid', on: true, tooltip: 'Applications'),
                const _Mini('chat', tooltip: 'Chat'),
                const SizedBox(width: 6),
              ],
              const _Mini('history', tooltip: 'Historique'),
            ]),
          ),
          Positioned(
            left: gridLeft,
            width: s.gridWidth,
            bottom: 8 + (20 - PageDots.height) / 2,
            child: Center(child: PageDots(count: pages, page: 0, onSelect: (_) {})),
          ),
          const Positioned(right: 14, bottom: 8, child: _Environment()),
        ],
      ),
    );
  }

  Widget _grid() {
    final s = spec;
    Widget cell(int i) {
      if (i < apps.length) {
        final a = apps[i];
        return AppTile(
          size: s.tile,
          label: a.name,
          status: a.status,
          onTap: () {},
          child: a.brand == null ? null : Center(child: BrandLogo(a.brand!, size: (s.tile * .34).roundToDouble())),
        );
      }
      if (i == apps.length) return AddTile(size: s.tile, onTap: () {});
      return AppSlot(size: s.tile);
    }

    return SizedBox(
      width: s.gridWidth,
      child: Wrap(spacing: s.gap, runSpacing: s.rowGap, children: [for (var i = 0; i < 6; i++) cell(i)]),
    );
  }
}

/// The modes, mini: 26 px high, icons 13 (44 and 18 before).
class _Modes extends StatelessWidget {
  const _Modes();

  @override
  Widget build(BuildContext context) => MTabBar(
    mini: true,
    height: 26,
    ink: true,
    selected: 0,
    onChanged: (_) {},
    items: const [TabItem('grid', label: 'Applications'), TabItem('chat', label: 'Chat')],
  );
}

/// A small control of the foot: an icon, 20 px round on hover.
class _Mini extends StatelessWidget {
  const _Mini(this.icon, {required this.tooltip, this.on = false});

  final String icon;
  final String tooltip;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Semantics(
      label: tooltip,
      button: true,
      child: HoverRow(
        onTap: () {},
        padding: const EdgeInsets.all(4),
        child: MikkyIcon(icon, size: 12, color: on ? ui.text : ui.text3),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Local', style: uiText(TextSize.caption, weight: FontWeight.w500, color: ui.text2)),
        const SizedBox(width: 5),
        const PixelStar(PixelFxPalette.grey, size: 9),
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Text('Rien en cours', style: uiText(TextSize.label, color: ui.text3)),
    );
  }
}

/// The latest task at a glance: its name, a few words of its state, its
/// steps (done, at work, to come). No messages, no card.
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
    final caption = switch (status) {
      AgentStatus.approval => 'Attend ton feu vert',
      AgentStatus.question => 'Te pose une question',
      AgentStatus.finished => _finished(turn, log),
      AgentStatus.rateLimited => log.detail,
      AgentStatus.error => 'En erreur',
      AgentStatus.idle || AgentStatus.paused => 'Arrêtée',
      _ => turn != null && turn.plan.isNotEmpty ? 'Au travail · ${planCount(planSteps(turn))}' : 'Au travail',
    };
    final captionColor = switch (status) {
      AgentStatus.approval || AgentStatus.question => ui.amber,
      AgentStatus.error => ui.red,
      AgentStatus.finished => ui.green,
      _ => ui.text3,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(children: [
          BrandLogo(task.brand, size: 12),
          const SizedBox(width: 6),
          Expanded(
            child: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.label, weight: FontWeight.w600, color: ui.text)),
          ),
        ]),
        const SizedBox(height: 2),
        Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, weight: FontWeight.w500, color: captionColor, tabular: true)),
        const SizedBox(height: 6),
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

  static String _finished(TurnSpan? turn, SessionLog log) {
    final start = log.items.firstOrNull?.at, end = log.lastEventAt;
    if (turn == null || start == null || end == null) return 'Terminée';
    final m = end.difference(start).inMinutes;
    return 'Terminée · ${m < 1 ? 'moins d’une min' : '$m min'}';
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

// ------------------------------------------------------------------ board

/// The other apps: the sample ones without the task Mikky looks at.
final _others = [for (final a in sampleApps) if (a.id != 'a2') a].take(5).toList();

NotchHome _notch(NotchTry spec, SessionLog? log, {String name = 'Corrige les tests du moteur', Brand brand = Brand.claude}) =>
    NotchHome(spec: spec, apps: _others, task: log == null ? null : NotchTask(name: name, brand: brand, log: log));

/// Before and after, side by side: the controls of the bar and the foot.
class _Sizes extends StatelessWidget {
  const _Sizes({required this.small});

  final bool small;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final h = small ? 26.0 : 44.0;
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
          if (small)
            const _Environment()
          else
            Text('Local  (36 px)', style: uiText(TextSize.label, weight: FontWeight.w600, color: ui.text)),
        ]),
      ]),
    );
  }
}

final notchBoard = BoardSpec('Notch', 'Essais du 5 octobre : l’accueil du haut plus large, Mikky qui regarde la dernière tâche', (context) => [
  BoardSection(
    title: 'Variantes',
    note: 'L’île du haut élargie. À gauche, Mikky en plus grand, tourné vers la dernière tâche au travail : son nom, son état en quelques mots, ses étapes (faites, en cours, à venir), sans les messages. À droite, les autres applications en 3 colonnes et 2 rangées. Les commandes réduites : modes et outils à 26 px (44 avant), historique et environnement en petit dans le pied. Pas de carte autour de la tâche.',
    frames: [
      BoardFrame(label: 'A · Barre fine', note: '580 × 188, tuiles de 46.', width: 580, child: _notch(NotchTry.thin, FakeSessions.working())),
      BoardFrame(label: 'B · Sans barre', note: '580 × 160 : les modes en tout petit dans le pied, « + » pour une tâche.', width: 580, child: _notch(NotchTry.bare, FakeSessions.working())),
      BoardFrame(label: 'C · Plus large', note: '640 × 212, Mikky à 96, tuiles de 52, cinq étapes.', width: 640, child: _notch(NotchTry.wide, FakeSessions.working())),
    ],
  ),
  BoardSection(
    title: 'La tâche que Mikky regarde',
    note: 'Sur la variante A. Seulement les étapes qui apparaissent, et la fin. Plus tard : Ctrl + clic ouvre l’agent dans son application (VS Code…).',
    frames: [
      BoardFrame(label: 'Au travail, avec un plan', width: 580, child: _notch(NotchTry.thin, FakeSessions.working())),
      BoardFrame(label: 'Au travail, sans plan', width: 580, child: _notch(NotchTry.thin, FakeSessions.workingNoPlan(), name: 'Ajoute un test Codex', brand: Brand.codex)),
      BoardFrame(label: 'Attend ton feu vert', width: 580, child: _notch(NotchTry.thin, FakeSessions.approval(), name: 'Met à jour le site', brand: Brand.codex)),
      BoardFrame(label: 'Terminée', width: 580, child: _notch(NotchTry.thin, FakeSessions.done())),
      BoardFrame(label: 'Limite atteinte', width: 580, child: _notch(NotchTry.thin, FakeSessions.limited())),
      BoardFrame(label: 'Rien en cours', note: 'Mikky dort.', width: 580, child: _notch(NotchTry.thin, null)),
    ],
  ),
  const BoardSection(
    title: 'Tailles',
    note: 'Les commandes d’aujourd’hui et les petites.',
    frames: [
      BoardFrame(label: 'Avant', child: _Sizes(small: false)),
      BoardFrame(label: 'Après', child: _Sizes(small: true)),
    ],
  ),
]);
