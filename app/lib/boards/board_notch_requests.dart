import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../home/home_frame.dart';
import '../home/home_layout.dart';
import '../island/content/brief_view.dart';
import '../side/question_card.dart';
import '../side/request_page.dart';
import '../side/session_steps.dart';
import '../ui/content/diff_view.dart';
import '../ui/content/side.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

/// What Mikky brings in the notch (2026-10-08), to validate on Notch Top
/// before it goes into the app (user, 2026-10-12): a request with its
/// task, a question card, the diff of a file.
List<BoardSection> notchRequestSections() => [
  BoardSection(
    title: 'Une demande · essai',
    kind: FrameKind.trial,
    note: 'Le notch va droit à ce qui t’attend, 700 × 260 : Mikky à gauche, dans l’état de l’agent ; à sa droite qui demande (un clic ouvre sa page ; Ctrl + clic, son terminal ou VS Code), ce que fait la tâche, puis la demande et ses réponses, plates. Le plus pressé d’abord — questions et feux verts, puis erreurs, puis limites ; les plus anciennes d’abord — « 2/3 » dans la série ; répondu, la suivante ; plus rien, l’île revient où elle était. « Plus tard » la laisse en attente. Touches : O / N / T (toujours), 1 à 4 pour les choix, Entrée.',
    frames: [
      BoardFrame(
        label: 'Aujourd’hui dans l’app',
        kind: FrameKind.app,
        note: 'Pour comparer : le compte des lignes est collé à la commande, rien ne s’ouvre.',
        width: 700,
        child: _request(FakeSessions.approvalEdit(), 'Corrige la fermeture auto', trial: false),
      ),
      BoardFrame(
        label: 'Feu vert sur un fichier',
        note: 'Le chemin du fichier, et « +3 −1 » à côté : un clic ouvre le diff.',
        width: 700,
        child: _request(FakeSessions.approvalEdit(), 'Corrige la fermeture auto'),
      ),
      BoardFrame(
        label: 'Feu vert sur une commande',
        width: 700,
        child: _request(FakeSessions.approval(), 'Met à jour le site'),
      ),
      BoardFrame(
        label: 'La deuxième de trois',
        width: 700,
        child: _request(FakeSessions.approval(), 'Met à jour le site', position: 2, total: 3),
      ),
      BoardFrame(label: 'Erreur', width: 700, child: _request(FakeSessions.error(), 'Corrige la fermeture auto')),
      BoardFrame(
        label: 'Limite atteinte',
        note: '« Terminer » : ne plus attendre ; « Relance auto » : l’agent reprend seul quand la limite passe.',
        width: 700,
        child: _request(FakeSessions.limited(), 'Corrige la fermeture auto'),
      ),
      BoardFrame(
        label: 'Terminée',
        note: 'Ses fichiers, chacun avec son compte : un clic ouvre leur diff.',
        width: 700,
        child: _request(FakeSessions.doneFiles(), 'Corrige la fermeture auto'),
      ),
    ],
  ),
  BoardSection(
    title: 'Une question · essai',
    kind: FrameKind.trial,
    note: 'La question d’un agent (son outil de questions, par ACP ou par ses hooks : la même carte). Plate comme la barre de réponses : chaque choix sur sa ligne, son numéro dans un petit carré, sa description en gris. « Ici, tu réponds » (choisi le 12 octobre) : un liseré de pixels sur trois colonnes le long de la question et de ses choix, à travers nos oranges point par point, plus clair vers la droite, plein à hauteur de la question, qui s’égrène vers le bas ; glitché en tranches. Plusieurs questions : leurs titres au-dessus, comme des onglets — celle où l’on est, un carré de pixels orange ; les répondues, une coche dans nos bleus (un clic y revient) ; les suivantes en gris. « Précédente » rouvre la question d’avant avec sa réponse : un autre choix la change, « Suivante » la garde ; « Envoyer » sur la dernière, « Tout passer » laisse tout le formulaire. « Autre… » ouvre une ligne pour écrire ; un second clic la referme et la vide.',
    frames: [
      BoardFrame(label: 'Un choix', width: 700, child: _request(FakeSessions.question(), 'Prépare le stockage')),
      BoardFrame(
        label: '« Autre… » ouvert',
        width: 700,
        child: _request(
          FakeSessions.questionMultiple(),
          'Ajoute des tests',
          question: const QuestionTrial(other: true),
        ),
      ),
      BoardFrame(
        label: 'Trois questions',
        note: 'La première répondue.',
        width: 700,
        child: _request(
          FakeSessions.questions(),
          'Prépare le stockage',
          question: const QuestionTrial(answers: {'db': 'SQLite'}),
        ),
      ),
      BoardFrame(
        label: 'Revenue sur une question',
        note: '« Précédente » (ou un clic sur une coche) : sa réponse est là, un autre choix la change.',
        width: 700,
        child: _request(
          FakeSessions.questions(),
          'Prépare le stockage',
          question: const QuestionTrial(answers: {'db': 'SQLite', 'when': 'À l’heure dite'}, at: 1),
        ),
      ),
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

/// A request in the notch, 700 × 260, as the island shows it.
Widget _request(
  SessionLog log,
  String name, {
  int position = 1,
  int total = 1,
  QuestionTrial question = const QuestionTrial(),
  bool trial = true,
}) {
  final status = log.statusAt(log.lastEventAt ?? DateTime(2026));
  final agent = Agent(
    id: name,
    name: name,
    status: status,
    startedAt: 0,
    statusSince: 0,
    provider: AgentProvider.claude,
    cwd: r'C:\Users\alexa\projet\mikky',
  );
  final limited = status == AgentStatus.rateLimited;
  void none() {}
  return HomeFrame(
    layout: HomeLayout.top,
    size: const Size(700, 260),
    child: Stack(
      children: [
        Positioned.fill(
          child: RequestView(
            place: RequestPlace.top,
            agent: agent,
            brief: briefOf(log, status),
            question: log.question,
            canAlways: canAlways(log),
            position: position,
            total: total,
            questionTrial: question,
            trial: trial,
            actions: BriefActions(
              answer: (_) {},
              answerQuestion: (_) {},
              open: none,
              later: trial ? none : null,
              finishLimit: limited ? none : null,
              enchant: limited ? none : null,
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
