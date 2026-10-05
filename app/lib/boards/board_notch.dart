import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../home/home_view.dart';
import '../home/new_task.dart';
import '../home/task_glance.dart';
import '../home/tools_rail.dart';
import '../ui/app_glyph.dart';
import '../ui/app_tile.dart';
import '../ui/dot_field.dart';
import '../ui/buttons.dart';
import '../ui/edge_rail.dart';
import '../ui/environment_selector.dart';
import '../ui/page_dots.dart';
import '../ui/side.dart';
import '../ui/status.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';
import '../ui/thread_page.dart';
import 'board_screens.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

// The notch (user, 2026-10-05): the home at the top since « Côte à côte »
// was chosen — Mikky looking at the latest task, the other apps as wide
// tiles with the software they run in. At the right, trials only for now.

/// The other apps, as the notch shows them: a title, a line that changes,
/// the software they run in.
const sampleNotchApps = [
  HomeApp(id: 'n1', name: 'Met à jour le site', line: 'Attend : npm run build', app: AgentApp.codex, status: UiStatus.approval),
  HomeApp(id: 'n2', name: 'Prépare le plan de l’API', line: 'Lit api.md', app: AgentApp.vscode, status: UiStatus.working),
  HomeApp(id: 'n3', name: 'Traduis la documentation', line: 'Limite atteinte · reprend à 17 h 10', app: AgentApp.terminal, status: UiStatus.limited),
  HomeApp(id: 'n4', name: 'Résume la spec', line: 'Terminée · il y a 5 min', app: AgentApp.claude, status: UiStatus.finished),
  HomeApp(id: 'n5', name: 'Corrige le clic en dehors', line: 'Terminée · il y a 12 min', app: AgentApp.vscode, status: UiStatus.finished),
  HomeApp(id: 'n6', name: 'Nettoie les imports', line: 'Terminée · hier', app: AgentApp.mikky, status: UiStatus.finished),
  HomeApp(id: 'n7', name: 'Ajoute les tests du lecteur', line: 'Terminée · hier', app: AgentApp.codex, status: UiStatus.finished),
];

/// A made-up task for Mikky to look at.
WatchedTask _watched(SessionLog log, {String name = 'Corrige les tests du moteur', AgentApp app = AgentApp.vscode}) =>
    WatchedTask(id: 'w', name: name, log: log, status: log.statusAt(log.lastEventAt ?? DateTime(2026)), app: app);

/// The notch in its window, on a board, its Mikky in the task's state.
/// The task he looks at is not among the apps, as in the app.
Widget _notch({WatchedTask? watched, List<HomeApp> apps = sampleNotchApps, DotFieldStyle? dots}) => HomeFrame(
  layout: HomeLayout.top,
  child: HomeView(
    layout: HomeLayout.top,
    apps: [for (final a in apps) if (a.name != watched?.name) a],
    watched: watched,
    animate: false,
    mikky: watched == null ? MikkyState.sleeping : mikkyStateOf(watched.status),
    onNew: () {},
    onHistory: (_) {},
    dots: dots,
  ),
);

/// An agent's page in the island at the top: taller than the notch.
Widget _page(Widget page) => HomeFrame(layout: HomeLayout.top, size: HomeLayout.top.pageSize, child: page);

/// A new chat in the notch's island, Mikky beside it.
class _NewChat extends StatelessWidget {
  const _NewChat({this.status, this.error});

  final String? status, error;

  @override
  Widget build(BuildContext context) => _page(OwnOverlay(child: NewChatSample(status: status, error: error, mikky: MikkyBeside.middle)));
}

final notchTopBoard = BoardSpec('Notch Top', 'L’accueil dans l’île en haut de l’écran : le notch', (context) => [
  BoardSection(
    title: 'Notch Top',
    note: 'L’accueil du haut depuis le 5 octobre (« Côte à côte »), 700 × 200, collé au bord de l’écran. À gauche, Mikky (96) et la dernière tâche au travail, qui s’étend jusqu’aux applications : le logiciel où elle tourne, son titre, son état en petit et gris avec sa progression (un segment par étape du plan), ses étapes un peu en retrait, sans les messages ; un clic l’ouvre. À droite, les autres applications en tuiles larges 160 × 42, 2 × 2 : titre, ligne qui change, logiciel ; les flèches de chaque côté quand il y en a d’autres. Modes et outils à 32 px, historique et environnement en petit.',
    frames: [
      BoardFrame(label: 'Dans l’app', note: 'Sept autres applications : deux pages, la flèche de droite.', width: 700, child: _notch(watched: _watched(FakeSessions.working()))),
      BoardFrame(
        label: 'Rien en cours',
        note: 'Mikky dort, plus grand (120) ; une troisième colonne prend la place de la tâche.',
        width: 700,
        child: _notch(apps: sampleNotchApps.skip(3).toList()),
      ),
      BoardFrame(label: 'Aucun agent', note: '« + » pour lancer une tâche, des petits points là où les applications viendront.', width: 700, child: _notch(apps: const [])),
    ],
  ),
  BoardSection(
    title: 'Essais · des points derrière les applications',
    note: 'Glitchés, retenus (5 octobre ; réguliers et deux foyers écartés). De petits points gris (1,6 px, tous les 8 px ; 1,2 et 6 en faisaient trop, trop petits), un peu plus foncés, une texture de loin : toujours là sous les applications, ils s’éteignent au hasard en allant vers la gauche jusqu’à disparaître, un peu dans la partie de Mikky. Deux versions : des carrés de 4 × 4 points, un sur trois très présent ; ou de grands carrés (6 × 6) plus ou moins présents, parsemés de petits carrés vifs (2 × 2).',
    kind: FrameKind.trial,
    frames: [
      for (final (label, style) in [('Glitchés', DotFieldStyle.glitch), ('Glitchés · grands et petits carrés', DotFieldStyle.glitchMixed)]) ...[
        BoardFrame(label: label, width: 700, child: _notch(watched: _watched(FakeSessions.working()), dots: style)),
        BoardFrame(label: '$label · rien en cours', width: 700, child: _notch(apps: sampleNotchApps.skip(3).toList(), dots: style)),
      ],
    ],
  ),
  BoardSection(
    title: 'La tâche que Mikky regarde',
    note: 'La dernière au travail ou qui attend ; sinon celle qui a fini il y a moins de 10 min. Seulement ses étapes qui apparaissent, et la fin. Sans plan : pas de progression.',
    frames: [
      BoardFrame(label: 'Au travail, sans plan', width: 700, child: _notch(watched: _watched(FakeSessions.workingNoPlan(), name: 'Ajoute un test Codex', app: AgentApp.terminal))),
      BoardFrame(label: 'Attend ton feu vert', width: 700, child: _notch(watched: _watched(FakeSessions.approval(), name: 'Met à jour le site', app: AgentApp.codex))),
      BoardFrame(label: 'Terminée', width: 700, child: _notch(watched: _watched(FakeSessions.done(), app: AgentApp.mikky))),
      BoardFrame(label: 'Limite atteinte', width: 700, child: _notch(watched: _watched(FakeSessions.limited(), app: AgentApp.claude))),
    ],
  ),
  BoardSection(
    title: 'Chat',
    note: 'Le mode Chat, « + » et les outils ouvrent un nouveau chat comme la page d’un agent (2026-10-05) : l’île passe à 700 × 380, la page arrive en fondu avec un léger zoom, Mikky glisse à gauche au milieu ; le fil est vide, « Qu’est-ce qu’on lance ? » en son milieu, le champ en bas avec le dossier et le modèle. Envoyer lance l’agent : la page devient la sienne, sur place.',
    frames: [
      const BoardFrame(label: 'Au départ', width: 700, child: _NewChat()),
      const BoardFrame(label: 'Démarrage', width: 700, child: _NewChat(status: 'Démarrage…')),
      const BoardFrame(label: 'Erreur', width: 700, child: _NewChat(error: 'Codex n’est pas installé dans WSL.')),
    ],
  ),
  BoardSection(
    title: 'La page d’un agent',
    note: 'Une tuile ou la tâche ouvre la page de l’agent : le fil (messages et actions ensemble), Oui / Non, la limite, le menu ···. L’île garde la largeur du notch : 700 × 380 ; la page arrive en fondu avec un léger zoom. Mikky (84) passe à gauche, au milieu de la hauteur, dans l’état de l’agent, tourné vers le fil ; le fil et le champ à sa droite. Dans l’app, c’est le Mikky de l’île qui glisse de l’accueil à cette place, doucement, comme s’il flottait. Le retour (bouton, Échap) ramène le notch.',
    frames: [
      BoardFrame(label: 'Au travail', width: 700, child: _page(AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.working(), framed: false, mikky: MikkyBeside.middle))),
      BoardFrame(label: 'Feu vert', width: 700, child: _page(AgentMock(title: 'Met à jour le site', log: FakeSessions.approval(), framed: false, mikky: MikkyBeside.middle))),
      BoardFrame(label: 'Terminé, la conversation continue', width: 700, child: _page(AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.done(), framed: false, mikky: MikkyBeside.middle))),
    ],
  ),
  const BoardSection(
    title: 'Fonctionnement',
    frames: [
      BoardFrame(
        label: 'Règles du notch',
        child: BoardRules([
          ('Taille', 'Île ouverte 700 × 200, coins bas 30 ; le haut dépasse de l’écran (fenêtre de l’île 840 × 480, pour l’ombre). Toujours 700 de large en haut : la page d’un agent 700 × 380, une demande de Mikky 700 × 260. Barre à 10 px du haut, 32 px de haut. La tâche de 46 à 166 ; le pied à 8 px du bas.'),
          ('Mikky', '96 px, à 8 px de sa tâche (190 de large, jusqu’à 4 px de la zone des applications) ; rien en cours, 120 px ; dans l’app, le Mikky de l’île vient s’y poser en ouvrant, dans l’état de la tâche. Rien en cours : il dort.'),
          ('La tâche', 'La dernière au travail ou qui attend ; sinon celle qui a fini il y a moins de 10 min ; sinon rien, et une colonne d’applications de plus. Logiciel (signe et nom), titre, état et progression, 3 étapes au plus, en retrait.'),
          ('Applications', 'Tuiles larges 160 × 42, 8 px d’écart, 2 × 2 (3 × 2 sans tâche) : le signe du logiciel, le titre, une ligne qui change ; l’état au coin. Le logiciel plutôt que le modèle : VS Code, Terminal, l’app Claude ou Codex, Mikky. Après elles, « + » (Nouvelle tâche, le Chat), puis un petit point à chaque place libre, là où les prochaines viendront.'),
          ('Pages', 'Elles glissent dans la partie droite : glisser à la souris ou au pavé, molette, flèches de 22 px de chaque côté des applications, à 6 px d’elles (effacées au bout), points, ← → au clavier.'),
          ('Pied', 'Historique en petit bouton de 24 à gauche ; les points sous les applications ; « Local » en petit (24 px) à droite.'),
          ('Plus tard', 'Ctrl + clic ouvre l’agent dans son logiciel. La vraie icône de VS Code, prise sur le PC.'),
        ]),
      ),
    ],
  ),
]);

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

/// A trial of the notch at the right edge, upright, 300 wide.
class NotchRight extends StatelessWidget {
  const NotchRight({super.key, this.task, this.style = RightStyle.center});

  static const width = 300.0;
  static const _content = 50.0, _bar = 32.0;

  final WatchedTask? task;
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
    final t = task;
    MiniMikky mikky(double size, {Offset look = const Offset(1, .3)}) =>
        MiniMikky(size: size, animate: false, badge: false, state: t == null ? MikkyState.sleeping : mikkyStateOf(t.status), look: look);
    final head = switch (style) {
      RightStyle.center => [
        Positioned(left: 0, right: 0, top: _content - 6, child: Center(child: mikky(76, look: const Offset(0, .7)))),
        if (t != null) Positioned(left: 20, right: 20, top: _content + 74, child: _Centered(task: t)),
      ],
      RightStyle.header => [
        Positioned(left: 10, top: _content - 4, child: mikky(60)),
        if (t != null) ...[
          Positioned(left: 74, right: 14, top: _content, height: 62, child: TaskGlance(task: t, steps: 0)),
          Positioned(left: 14, right: 14, top: _content + 72, child: TaskSteps(log: t.log, waiting: t.status == AgentStatus.approval)),
        ],
      ],
      RightStyle.dock => [
        Positioned(left: 10, top: _content + (top - 72) / 2, child: mikky(72)),
        if (t != null) Positioned(left: 84, right: 14, top: _content, height: top, child: TaskGlance(task: t)),
      ],
    };
    const appsW = width - 32;
    final apps = sampleNotchApps.take(4);
    final Widget grid = switch (style) {
      RightStyle.center => Column(children: [
        for (final a in apps) Padding(padding: const EdgeInsets.only(bottom: 6), child: _Wide(app: a, width: appsW, height: 40)),
      ]),
      RightStyle.header => Wrap(spacing: 10, runSpacing: 10, children: [for (final a in apps) _IconAndWords(app: a, width: (appsW - 10) / 2)]),
      RightStyle.dock => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final a in apps) AppTile(size: 44, label: a.name, status: a.status, onTap: () {}, child: Center(child: AppGlyph(a.app!, size: 16))),
        AddTile(size: 44, onTap: () {}),
      ]),
    };
    return HomeFrame(
      layout: HomeLayout.right,
      size: Size(width, height),
      child: Stack(clipBehavior: Clip.none, children: [
        ...head,
        Positioned(left: 16, right: 16, top: _content + top + 12, child: grid),
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(
            child: MTabBar(mini: true, height: _bar, ink: true, selected: 0, onChanged: (_) {}, items: const [TabItem('grid', label: 'Applications'), TabItem('chat', label: 'Chat')]),
          ),
        ),
        Positioned(top: 10, right: 0, child: ToolsRail(edge: RailEdge.right, height: _bar, onPressed: () {})),
        Positioned(left: 12, bottom: 8, child: RoundButton('history', size: 24, ghost: true, tooltip: 'Historique', onPressed: () {})),
        Positioned(left: 0, right: 0, bottom: 8 + (24 - PageDots.height) / 2, child: Center(child: PageDots(count: 2, page: 0, onSelect: (_) {}))),
        Positioned(right: 12, bottom: 8, child: EnvironmentSelector(selected: MikkyEnvironment.local, onChanged: (_) {}, menuWithin: context, small: true)),
      ]),
    );
  }
}

/// The title and the line under it.
Widget _words(HomeApp a, MikkyUi ui) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text, height: 1.25)),
  const SizedBox(height: 1),
  Text(a.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.caption, color: ui.text3, height: 1.25)),
]);

/// A wide tile, as in the notch at the top.
class _Wide extends StatelessWidget {
  const _Wide({required this.app, required this.width, required this.height});

  final HomeApp app;
  final double width, height;

  @override
  Widget build(BuildContext context) => AppTile(
    size: height,
    width: width,
    label: app.name,
    status: app.status,
    onTap: () {},
    child: Padding(
      padding: const EdgeInsets.only(left: 11, right: 12),
      child: Row(children: [
        SizedBox(width: 16, child: Center(child: AppGlyph(app.app!, size: 15))),
        const SizedBox(width: 9),
        Expanded(child: _words(app, MikkyUi.of(context))),
      ]),
    ),
  );
}

/// A small tile with the sign, the words beside it.
class _IconAndWords extends StatelessWidget {
  const _IconAndWords({required this.app, required this.width});

  final HomeApp app;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 44,
    child: Row(children: [
      AppTile(size: 40, label: app.name, status: app.status, onTap: () {}, child: Center(child: AppGlyph(app.app!, size: 15))),
      const SizedBox(width: 9),
      Expanded(child: _words(app, MikkyUi.of(context))),
    ]),
  );
}

/// The task centered under Mikky: the software, the title, the state.
class _Centered extends StatelessWidget {
  const _Centered({required this.task});

  final WatchedTask task;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final p = progressOf(task.log);
    final waiting = task.status == AgentStatus.approval;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (task.app != null) AppLine(task.app!),
      const SizedBox(height: 4),
      Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: uiText(TextSize.label, weight: FontWeight.w600, color: ui.text)),
      const SizedBox(height: 3),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(waiting ? 'Attend ton feu vert' : 'Au travail', style: uiText(TextSize.caption, weight: FontWeight.w500, color: waiting ? ui.amber : ui.text3)),
        if (p != null) ...[const SizedBox(width: 8), TaskProgress(done: p.$1, total: p.$2, color: waiting ? ui.amber : ui.blue)],
      ]),
    ]);
  }
}

final notchRightBoard = BoardSpec('Notch Right', 'L’accueil de droite à venir : des essais', (context) => [
  BoardSection(
    title: 'Notch Right',
    kind: FrameKind.trial,
    note: '300 de large, collé au bord droit, avec les pièces du notch du haut. Trois idées, après la première (Mikky à côté de sa tâche, au-dessus d’une liste) qui ne convainquait pas. Dans l’app, la droite reste l’accueil de la planche Accueil Right en attendant.',
    frames: [
      BoardFrame(
        label: 'Au centre',
        note: 'Mikky au milieu en haut, le regard vers sa tâche dessous : logiciel, titre, état ; pas d’étapes. Les applications en liste.',
        width: 300,
        child: NotchRight(task: _watched(FakeSessions.working())),
      ),
      BoardFrame(
        label: 'En-tête',
        note: 'Mikky petit à côté du logiciel et du titre, les étapes dessous sur toute la largeur ; les applications 2 × 2 en icônes et mots.',
        width: 300,
        child: NotchRight(task: _watched(FakeSessions.working()), style: RightStyle.header),
      ),
      BoardFrame(
        label: 'Dock',
        note: 'Mikky à côté de sa tâche ; les applications en une rangée de petites tuiles, comme un dock (les mots au survol). Le plus court.',
        width: 300,
        child: NotchRight(task: _watched(FakeSessions.working()), style: RightStyle.dock),
      ),
    ],
  ),
  BoardSection(
    title: 'Attend ton feu vert',
    kind: FrameKind.trial,
    frames: [
      for (final (label, style) in [('Au centre', RightStyle.center), ('En-tête', RightStyle.header), ('Dock', RightStyle.dock)])
        BoardFrame(label: label, width: 300, child: NotchRight(task: _watched(FakeSessions.approval(), name: 'Met à jour le site', app: AgentApp.codex), style: style)),
    ],
  ),
]);
