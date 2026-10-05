import 'package:flutter/widgets.dart';

import '../home/history_sheet.dart';
import '../home/home_view.dart';
import '../home/new_task.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/environment_selector.dart';
import '../ui/page_dots.dart';
import '../ui/sheet.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'board_notch.dart' show sampleNotchApps;
import 'board_screens.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

// The home at the right (2026-10-02); the one at the top is the notch
// (`board_notch.dart`). Its components are on the Composants board. The
// HTML mockups of `docs/notch_haut/` are only a picture of the goal.

/// Components on the island's color, for the boards. [edge]: flat on the
/// right, as against the screen's edge, and the content right up to it.
class BoardPane extends StatelessWidget {
  const BoardPane({super.key, required this.child, this.width = 300, this.height, this.edge = false});

  final Widget child;
  final double width;
  final double? height;
  final bool edge;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    const r = Radius.circular(Radii.xl);
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.fromLTRB(18, 18, edge ? 0 : 18, 18),
      decoration: BoxDecoration(
        color: ui.island,
        borderRadius: edge ? const BorderRadius.horizontal(left: r) : const BorderRadius.all(r),
        border: edge ? Border(left: BorderSide(color: ui.line), top: BorderSide(color: ui.line), bottom: BorderSide(color: ui.line)) : Border.all(color: ui.line),
      ),
      child: child,
    );
  }
}

/// The arrows and the dots of the home's pages, to try.
class PagerTry extends StatelessWidget {
  const PagerTry({super.key, required this.page, required this.set, this.count = 4});

  final int page, count;
  final ValueChanged<int> set;

  @override
  Widget build(BuildContext context) {
    Widget arrow(bool next) {
      final shown = next ? page < count - 1 : page > 0;
      return Opacity(
        opacity: shown ? 1 : 0,
        child: RoundButton(next ? 'right' : 'left', size: 28, onPressed: shown ? () => set(page + (next ? 1 : -1)) : null),
      );
    }

    return Row(children: [
      arrow(false),
      Expanded(child: Center(child: PageDots(count: count, page: page, onSelect: set))),
      arrow(true),
    ]);
  }
}

/// « Choisir l'environnement » in a little window of its own (with an
/// Overlay, as the app's): the real menu opens in it.
class SelectorTry extends StatefulWidget {
  const SelectorTry({super.key});

  @override
  State<SelectorTry> createState() => _SelectorTryState();
}

class _SelectorTryState extends State<SelectorTry> {
  MikkyEnvironment _environment = MikkyEnvironment.local;
  late final OverlayEntry _layer = OverlayEntry(
    builder: (inner) => Stack(children: [
      Positioned(
        top: 18,
        right: 18,
        child: EnvironmentSelector(
          selected: _environment,
          menuWithin: inner,
          onChanged: (e) {
            _environment = e;
            _layer.markNeedsBuild();
          },
        ),
      ),
    ]),
  );

  @override
  void dispose() {
    _layer.remove();
    _layer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: 300,
      height: 250,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: ui.island, borderRadius: BorderRadius.circular(Radii.xl), border: Border.all(color: ui.line)),
      child: Overlay(initialEntries: [_layer]),
    );
  }
}

// ------------------------------------------------------------------ boards

/// Apps as the app shows them today: the tool's logo and the agent's state
/// (until the apps get their drawing).
const sampleApps = [
  HomeApp(id: 'a1', name: 'Met à jour le site', brand: Brand.codex, status: UiStatus.approval),
  HomeApp(id: 'a2', name: 'Corrige les tests du moteur', brand: Brand.claude, status: UiStatus.working),
  HomeApp(id: 'a3', name: 'Prépare le plan de l’API', brand: Brand.codex, status: UiStatus.working),
  HomeApp(id: 'a4', name: 'Traduis la documentation', brand: Brand.claude, status: UiStatus.limited),
  HomeApp(id: 'a5', name: 'Résume la spec', brand: Brand.claude, status: UiStatus.finished),
  HomeApp(id: 'a6', name: 'Ajoute les tests du lecteur', brand: Brand.codex, status: UiStatus.finished),
  HomeApp(id: 'a7', name: 'Nettoie les imports', brand: Brand.codex, status: UiStatus.working),
  HomeApp(id: 'a8', name: 'Corrige le clic en dehors', brand: Brand.claude, status: UiStatus.finished),
];

/// A home in its window, on a board.
Widget _home(HomeLayout layout, List<HomeApp> apps) => HomeFrame(layout: layout, child: HomeView(layout: layout, apps: apps, onNew: () {}));

/// The home on its Chat, on a board.
Widget _chat(HomeLayout layout, {String? status, String? error}) => HomeFrame(
  layout: layout,
  child: HomeView(layout: layout, apps: sampleApps, inChat: true, chat: (_) => NewTaskSample(status: status, error: error)),
);

/// An agent's page in the island, taller than the home.
Widget _page(HomeLayout layout, Widget page) => HomeFrame(layout: layout, size: layout.pageSize, child: page);

const _appRule = ('Application', 'Un ou plusieurs agents qui font une tâche. Dans l’app aujourd’hui : un agent, le logo de son outil et son état ; le dessin des applications viendra.');
const _pagesRule = ('Pages', 'Elles glissent de côté sur toute la largeur (380 ms) : glisser à la souris ou au pavé, molette (une page par cran), flèches grises de 28 px effacées au bout, l’étoile des pages (clic sur un point), ← → au clavier.');
const _whichRule = ('Lesquelles', 'Ceux qui attendent, ceux qui travaillent, puis les 5 derniers terminés du jour (épinglés d’abord). Pas l’historique ni les archives : ils auront leur place ailleurs.');
const _modesRule = ('Modes', 'En haut au milieu. Applications ou chat, le choix en noir : le seul noir de l’écran, sa profondeur (2 octobre). Vers le chat, un fondu doux avec un léger zoom (300 ms) ; retour aux applications, vif : le chat part en 70 ms, les tuiles arrivent en 160 ms, le pied en 120 ms.');
const _chatRule = ('Chat', 'Le « Nouvel agent » d’avant, dans l’accueil : « Qu’est-ce qu’on lance ? » au milieu, le champ en bas avec le dossier et le modèle (où, permissions) à moitié dedans ; le pied (historique, étoile, environnement) s’efface. « + » et les outils y mènent. Envoyer lance l’agent : sa page s’ouvre, l’accueil revient aux applications, où il apparaît.');
const _mikkyRule = ('Mikky', 'Dans l’app, le Mikky de l’île vient s’y poser en ouvrant (72 px) et garde l’état de l’agent qu’il suit ; sur les planches, le même Mikky en petit.');


final homeRightBoard = BoardSpec(
  'Accueil Right',
  'L’accueil dans l’île à droite de l’écran',
  (context) => [
    BoardSection(
      title: 'Accueil Right',
      note: 'L’ancien accueil du haut, debout (2 octobre : « une version verticale de la version haut ») : tuiles de 64 px, huit applications par page en 2 × 4, dans l’île ouverte à droite, 290 × 408, plate du côté de l’écran. Sur la page d’un agent, elle grandit en forme de téléphone, 344 × 520. Le notch viendra ici aussi (planche Notch Right, essais).',
      frames: [
        BoardFrame(label: 'Dans l’app', note: 'Un clic : la page de l’agent ; « + » et les outils : le Chat.', width: 290, child: _home(HomeLayout.right, sampleApps)),
        BoardFrame(label: 'Trois pages · tuiles neutres', note: 'Vingt applications, 8 par page.', width: 290, child: _home(HomeLayout.right, HomeApp.placeholders(20))),
        BoardFrame(label: 'Aucun agent', width: 290, child: _home(HomeLayout.right, const [])),
      ],
    ),
    BoardSection(
      title: 'Chat',
      note: 'Le même Chat que dans le notch : le « Nouvel agent » d’avant, dans l’accueil.',
      frames: [
        BoardFrame(label: 'Au départ', width: 290, child: _chat(HomeLayout.right)),
        BoardFrame(label: 'Démarrage', width: 290, child: _chat(HomeLayout.right, status: 'Démarrage…')),
      ],
    ),
    BoardSection(
      title: 'La page d’un agent',
      note: 'Une tuile ouvre la page de l’agent, et l’île grandit en forme de téléphone pour la conversation, 344 × 520, sur le même ressort ; le retour (bouton, Échap) la ramène à 290 × 408.',
      frames: [
        BoardFrame(label: 'Au travail', width: 344, child: _page(HomeLayout.right, AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.working(), framed: false))),
        BoardFrame(label: 'Feu vert', width: 344, child: _page(HomeLayout.right, AgentMock(title: 'Met à jour le site', log: FakeSessions.approval(), framed: false))),
      ],
    ),
    const BoardSection(
      title: 'Fonctionnement',
      frames: [
        BoardFrame(
          label: 'Règles de l’accueil Right',
          child: BoardRules([
            ('Taille', 'Île ouverte 290 × 408, coins gauches 30 ; le côté droit dépasse de l’écran (fenêtre de l’île 420 × 700). Barre à 12 px du haut, 44 px de haut, puis 10 px entre la barre, les tuiles, le pied et le bord. Sur la page d’un agent : 344 × 520, sur le même ressort.'),
            _appRule,
            _whichRule,
            ('Tuiles', '64 px, 2 colonnes (16 d’écart) × 4 rangées (10 d’écart), 8 par page, la dernière page remplie depuis la gauche ; flèches à 18 px des bords.'),
            _pagesRule,
            ('Actions', 'Une tuile : la page de l’agent (le fil, Oui / Non, limite…). « + » et les outils : le Chat. L’historique, en bas à gauche : la liste par-dessus ; un agent rouvert revient parmi les applications. Clic droit : le menu de Mikky (thème, position, notifications…).'),
            _modesRule,
            _chatRule,
            _mikkyRule,
          ]),
        ),
      ],
    ),
  ],
);

// ---------------------------------------------------------------- history

/// The history's rows, as sample data.
const sampleHistory = <HistoryRow>[
  (id: 'h1', title: 'Ajoute la position à droite', brand: Brand.claude, when: 'Hier'),
  (id: 'h2', title: 'Traduis le README', brand: Brand.codex, when: 'Hier · WSL'),
  (id: 'h3', title: 'Corrige le hook souris', brand: Brand.claude, when: 'Lundi'),
  (id: 'h4', title: 'Prépare la démo de l’île', brand: Brand.claude, when: 'Lundi'),
  (id: 'h5', title: 'Nettoie les imports du moteur', brand: Brand.codex, when: '28 sept.'),
  (id: 'h6', title: 'Écris les tests du lecteur Codex', brand: Brand.codex, when: '28 sept. · WSL'),
  (id: 'h7', title: 'Résume la spec de mikkyd', brand: Brand.claude, when: '27 sept.'),
  (id: 'h8', title: 'Ajoute le menu flottant', brand: Brand.claude, when: '26 sept.'),
  (id: 'h9', title: 'Mesure le CPU de l’île', brand: Brand.codex, when: '25 sept.'),
];

void _noId(String _) {}

/// A home with its history button: the history opens over it, for real,
/// at the right or in the notch.
class HistoryTry extends StatelessWidget {
  const HistoryTry({super.key, this.layout = HomeLayout.right});

  final HomeLayout layout;

  @override
  Widget build(BuildContext context) => HomeFrame(
    layout: layout,
    child: HomeView(
      layout: layout,
      apps: layout.isTop ? sampleNotchApps : sampleApps,
      animate: false,
      onNew: () {},
      onHistory: (within) => showHistory(within, rows: sampleHistory, onMenu: _noId),
    ),
  );
}

/// The same, the history open and still (for the pictures).
class HistoryOpen extends StatelessWidget {
  const HistoryOpen({super.key, this.layout = HomeLayout.right});

  final HomeLayout layout;

  @override
  Widget build(BuildContext context) => HomeFrame(
    layout: layout,
    child: Stack(children: [
      HomeView(layout: layout, apps: layout.isTop ? sampleNotchApps : sampleApps, animate: false, onNew: () {}, onHistory: (_) {}),
      Positioned.fill(
        child: SheetScene(
          t: 1,
          panel: SheetPanel(
            title: 'Historique',
            caption: '${sampleHistory.length}',
            onClose: () {},
            child: const HistoryBody(rows: sampleHistory, onMenu: _noId),
          ),
        ),
      ),
    ]),
  );
}
