import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../home/home_app.dart';
import '../home/home_frame.dart';
import '../home/home_layout.dart';
import '../home/home_view.dart';
import '../home/notch_request.dart';
import '../island/content/brief_view.dart';
import '../ui/content/diff_view.dart';
import '../ui/content/side.dart';
import '../ui/foundation/status.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

BoardSection inlineRequestSection() => const BoardSection(
  title: 'Oui / Non · les applications restent visibles',
  kind: FrameKind.play,
  note:
      'Le feu vert remplace le suivi à gauche dans le notch de 700 × 200 ; quatre applications restent visibles à droite. '
      'Oui / Non répondent, Plus tard garde la demande en attente. Les boutons restent à gauche et le contenu long défile.',
  frames: [BoardFrame(label: 'Oui / Non / Plus tard', width: 700, child: NotchRequestDemo())],
);

BoardSection expandedQuestionSection() => const BoardSection(
  title: 'Une question en grand',
  kind: FrameKind.play,
  note:
      'Le notch s’agrandit à 700 × 260 pour la question : Mikky à gauche, les choix sur une colonne, '
      'les boutons à gauche et aucune autre application. Répondre ramène l’accueil ; Plus tard laisse la question en attente.',
  frames: [
    BoardFrame(
      label: 'Une question à la fois',
      kind: FrameKind.play,
      width: 700,
      child: NotchRequestDemo(question: true),
    ),
    BoardFrame(
      label: 'Plusieurs réponses possibles',
      kind: FrameKind.play,
      width: 700,
      child: NotchRequestDemo(question: true, multiple: true),
    ),
  ],
);

class NotchRequestDemo extends StatefulWidget {
  const NotchRequestDemo({super.key, this.question = false, this.readOnly = false, this.multiple = false});
  final bool question, readOnly, multiple;
  @override
  State<NotchRequestDemo> createState() => NotchRequestDemoState();
}

class NotchRequestDemoState extends State<NotchRequestDemo> {
  String get _name => widget.question
      ? widget.multiple
            ? 'Ajoute des tests'
            : 'Prépare le stockage'
      : 'Met à jour le site';

  SessionLog _freshLog() => widget.question
      ? widget.multiple
            ? FakeSessions.questionMultiple()
            : FakeSessions.questions()
      : FakeSessions.approval();

  late SessionLog _log = _freshLog();
  bool _shown = true, _answered = false;

  void _finish() => setState(() {
    _shown = false;
    _answered = true;
  });
  void _reopen() => setState(() {
    if (_answered) _log = _freshLog();
    _answered = false;
    _shown = true;
  });

  @override
  Widget build(BuildContext context) => HomeFrame(
    layout: HomeLayout.top,
    size: _shown && widget.question ? HomeLayout.questionSize : null,
    child: HomeView(
      animate: false,
      mikky: _shown ? MikkyState.approval : MikkyState.working,
      request: !_shown
          ? null
          : NotchRequest(
              name: _name,
              log: _log,
              onAnswer: widget.readOnly ? null : (_) => _finish(),
              onAnswerQuestion: widget.readOnly ? null : (_) => _finish(),
              onLater: () => setState(() => _shown = false),
              onOpen: () {},
            ),
      apps: [
        if (!_shown)
          HomeApp(
            id: 'request',
            name: _answered ? 'Rejouer la demande' : _name,
            app: AgentApp.codex,
            status: _answered ? UiStatus.working : UiStatus.approval,
          ),
        const HomeApp(
          id: 'guide',
          name: 'Rédige le guide',
          line: 'Relit les exemples',
          app: AgentApp.vscode,
          status: UiStatus.working,
        ),
        const HomeApp(
          id: 'tests',
          name: 'Teste le moteur',
          line: 'Lance les tests',
          app: AgentApp.terminal,
          status: UiStatus.working,
        ),
        const HomeApp(
          id: 'notes',
          name: 'Range les notes',
          line: 'Classe les sources',
          app: AgentApp.claude,
          status: UiStatus.working,
        ),
        const HomeApp(
          id: 'stars',
          name: 'Anime les étoiles',
          line: 'Vérifie le rendu',
          app: AgentApp.mikky,
          status: UiStatus.working,
        ),
      ],
      onOpen: (app) {
        if (app.id == 'request') _reopen();
      },
    ),
  );
}

/// Alerts that still need their own page, and file changes.
List<BoardSection> notchRequestSections() => [
  BoardSection(
    title: 'Les autres alertes',
    note: 'Les erreurs, limites et tâches terminées gardent leur page avec le contexte et les actions de l’app.',
    frames: [
      BoardFrame(label: 'Erreur', width: 700, child: _alert(FakeSessions.error(), 'Corrige la fermeture auto')),
      BoardFrame(
        label: 'Limite atteinte',
        width: 700,
        child: _alert(FakeSessions.limited(), 'Corrige la fermeture auto'),
      ),
      BoardFrame(label: 'Terminée', width: 700, child: _alert(FakeSessions.doneFiles(), 'Corrige la fermeture auto')),
    ],
  ),
  BoardSection(
    title: 'Le diff d’un fichier · essai',
    kind: FrameKind.trial,
    note: 'Un clic sur « +N −M » (une demande, une tâche terminée, le fil d’un agent) ouvre le diff du fichier dans l’île, 700 × 380 comme la page d’un agent : son nom, son dossier, ses lignes en mono, numérotées. Choisi le 12 octobre, « grain » : une ligne ajoutée teintée de notre bleu, une retirée de notre orange, et à côté du numéro un grain de pixels sur trois colonnes, à travers nos bleus (ou nos oranges) le long de chaque suite de lignes, glitché en tranches comme le liseré des questions ; le code changé ressort, le reste se tait. Trois lignes inchangées autour de chaque changement, les longues suites pliées (un clic les déplie). Le code sur une surface à points, comme Nothing (`DotSurface`) : blanche à points gris très clairs en clair, noire à points pâles en sombre.',
    frames: [
      BoardFrame(label: 'Deux changements, le milieu plié', width: 700, child: _diff([FakeSessions.islandEdit])),
      BoardFrame(label: 'Nouveau fichier', width: 700, child: _diff([FakeSessions.newTest])),
      BoardFrame(
        label: 'Modifié deux fois',
        note: 'Chaque modification à la suite, « Modification 1 sur 2 ».',
        width: 700,
        child: _diff([
          FakeSessions.islandEdit,
          FileDiff(
            FakeSessions.islandEdit.path,
            FakeSessions.islandEdit.newText,
            FakeSessions.islandEdit.newText.replaceAll('45.0', '30.0'),
            line: 1,
          ),
        ]),
      ),
    ],
  ),
];

/// Where the island draws Mikky in a request (`IslandMetrics.top.mikkyOpen`:
/// his center at (54, 88), radius 28; a [MiniMikky]'s center is at half
/// its width and 54 % of its height, its radius 29 % of it).
const _mikkySize = 96.0;
const _mikkyAt = Offset(54 - _mikkySize / 2, 88 - _mikkySize * .54);

/// The remaining focus alerts, using the app's pinned brief.
Widget _alert(SessionLog log, String name) {
  final status = log.statusAt(log.lastEventAt ?? DateTime(2026));
  final agent = Agent(
    id: name,
    name: name,
    status: status,
    startedAt: 0,
    statusSince: 0,
    provider: AgentProvider.claude,
    cwd: r'C:\Users\sam\projet\mikky',
  );
  final limited = status == AgentStatus.rateLimited;
  void none() {}
  return HomeFrame(
    layout: HomeLayout.top,
    size: const Size(700, 260),
    child: Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(104, 16, 18, 10),
            child: BriefView(
              agent: agent,
              brief: briefOf(log, status),
              pinned: true,
              actions: BriefActions(
                answer: (_) {},
                open: none,
                later: none,
                finishLimit: limited ? none : null,
                enchant: limited ? none : null,
              ),
            ),
          ),
        ),
        Positioned(
          left: _mikkyAt.dx,
          top: _mikkyAt.dy,
          child: MiniMikky(size: _mikkySize, animate: false, badge: false, state: mikkyStateOf(status)),
        ),
      ],
    ),
  );
}

/// The diff of a file in the notch, 700 × 380 like an agent's page.
Widget _diff(List<FileDiff> changes) => HomeFrame(
  layout: HomeLayout.top,
  size: HomeLayout.top.pageSize,
  child: DiffPage(path: changes.first.path, changes: changes, back: () {}),
);
