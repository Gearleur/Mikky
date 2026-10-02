import 'package:flutter/widgets.dart';

import '../home/home_view.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/environment_selector.dart';
import '../ui/page_dots.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'canvas.dart';

// The new home (2026-10-02): its components are on the Composants board,
// here the two placements. The HTML mockups of `docs/notch_haut/` are
// only a picture of the goal.

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
  HomeApp(id: 'a7', name: 'Corrige le clic en dehors', brand: Brand.claude),
  HomeApp(id: 'a8', name: 'Traduis le README', brand: Brand.codex),
  HomeApp(id: 'a9', name: 'Ajoute la position à droite', brand: Brand.claude),
];

/// A home in its window, on a board.
Widget _home(HomeLayout layout, List<HomeApp> apps) => HomeFrame(layout: layout, child: HomeView(layout: layout, apps: apps, onTools: () {}));

const _appRule = ('Application', 'Un ou plusieurs agents qui font une tâche. Dans l’app aujourd’hui : un agent, le logo de son outil et son état ; le dessin des applications viendra.');
const _pagesRule = ('Pages', 'Elles glissent de côté sur toute la largeur (380 ms) : glisser à la souris ou au pavé, molette (une page par cran), flèches grises de 28 px effacées au bout, points (clic), ← → au clavier.');
const _modesRule = ('Modes', 'Applications ou chat, le choix en noir : le seul noir de l’écran, sa profondeur (2 octobre). Le contenu passe de l’un à l’autre en fondu (300 ms). Le chat reste à dessiner.');
const _mikkyRule = ('Mikky', 'Dans l’app, le Mikky de l’île vient s’y poser en ouvrant (72 px) et garde l’état de l’agent qu’il suit ; sur les planches, le même Mikky en petit.');

final homeTopBoard = BoardSpec(
  'Accueil Top',
  'L’accueil dans l’île en haut de l’écran',
  (context) => [
    BoardSection(
      title: 'Accueil Top',
      note: 'L’île ouverte en haut par l’utilisateur (survol, clic), collée au bord de l’écran (plate en haut), à sa vraie taille : 450 × 260 (hauteur validée). Mikky vivant en haut à gauche, les modes au milieu, les outils sortis du bord à droite ; deux rangées de quatre applications par page ; les points et « Choisir l’environnement » en bas.',
      frames: [
        BoardFrame(label: 'Dans l’app', note: 'Les agents : logo de l’outil, état au coin. Un clic : l’agent en grand (ses réponses), Échap ou un clic : retour.', width: 450, child: _home(HomeLayout.top, sampleApps)),
        BoardFrame(label: 'Trois pages · tuiles neutres', note: 'Vingt applications, 8 par page.', width: 450, child: _home(HomeLayout.top, HomeApp.placeholders(20))),
        BoardFrame(label: 'Aucun agent', width: 450, child: _home(HomeLayout.top, const [])),
      ],
    ),
    const BoardSection(
      title: 'Fonctionnement',
      frames: [
        BoardFrame(
          label: 'Règles de l’accueil Top',
          child: BoardRules([
            ('Taille', 'Île ouverte 450 × 260, coins bas 30 ; le haut dépasse de l’écran (fenêtre de l’île 560 × 360 pour l’ombre). Barre à 12 px du haut, 44 px de haut ; puis 10 px entre la barre, les tuiles, le pied et le bord.'),
            ('Quand', 'Ouverte par l’utilisateur : l’accueil. Un agent qui attend : l’île prend la taille de la vue d’un agent (430 × 178) avec Oui / Non, comme avant.'),
            _appRule,
            ('Tuiles', '64 px, 16 px entre les colonnes, 10 entre les rangées ; 8 par page, la dernière page remplie depuis la gauche.'),
            _pagesRule,
            _modesRule,
            _mikkyRule,
          ]),
        ),
      ],
    ),
  ],
);

final homeRightBoard = BoardSpec(
  'Accueil Right',
  'L’accueil dans l’île à droite de l’écran',
  (context) => [
    BoardSection(
      title: 'Accueil Right',
      note: 'La même vue que l’accueil Top (mêmes composants, autre disposition) dans l’île ouverte à droite : 344 × 520, plate du côté de l’écran. Six applications par page (2 × 3), qui glissent de côté comme en haut ; « Choisir l’environnement » en haut au milieu, les points puis les modes en bas.',
      frames: [
        BoardFrame(label: 'Dans l’app', note: 'Un clic ouvre la page de l’agent ; les outils, un nouvel agent.', width: 344, child: _home(HomeLayout.right, sampleApps)),
        BoardFrame(label: 'Trois pages · tuiles neutres', note: 'Quinze applications, 6 par page.', width: 344, child: _home(HomeLayout.right, HomeApp.placeholders(15))),
        BoardFrame(label: 'Aucun agent', width: 344, child: _home(HomeLayout.right, const [])),
      ],
    ),
    const BoardSection(
      title: 'Fonctionnement',
      frames: [
        BoardFrame(
          label: 'Règles de l’accueil Right',
          child: BoardRules([
            ('Taille', 'Île ouverte 344 × 520 (celle d’aujourd’hui), coins gauches 38 ; le côté droit dépasse de l’écran.'),
            _appRule,
            ('Tuiles', '100 px, 2 colonnes (24 d’écart) × 3 rangées (20 d’écart) : 6 par page, au milieu entre la barre et les points.'),
            _pagesRule,
            ('Actions', 'Une tuile : la page de l’agent (Suivi, Chat, Oui / Non, limite…). Les outils : un nouvel agent. Clic droit : le menu de Mikky (thème, position, notifications…).'),
            _modesRule,
            _mikkyRule,
          ]),
        ),
      ],
    ),
  ],
);
