import 'package:flutter/widgets.dart';

import '../home/history_sheet.dart';
import '../home/home_frame.dart';
import '../home/home_layout.dart';
import '../home/home_view.dart';
import '../overlay/overlay_channel.dart';
import '../ui/brand/brand_logo.dart';
import '../ui/content/history_view.dart';
import '../ui/foundation/status.dart';
import '../ui/overlays/floating_menu.dart';
import '../ui/overlays/sheet.dart';
import 'board_notch.dart' show sampleNotchApps;
import 'canvas.dart';

(String, List<Widget>) historyComponents() => (
  'Historique',
  [
    const BoardSection(
      title: 'Historique · dans l’app',
      note: 'Une colonne, quatre conversations visibles. Apparition plus progressive ; la navigation sort à gauche sur le ressort de « Petite île → bulle en haut », avec la même fusion des formes adaptée à une barre. Les commandes restent utilisables pendant le mouvement.',
      frames: [
        BoardFrame(
          kind: FrameKind.app,
          label: 'Retenu · une colonne, quatre conversations',
          note: 'La version à garder. La flèche revient à l’accueil ; son bouton Historique permet de rejouer l’apparition.',
          width: 700,
          child: HistoryTopPreview(
            key: ValueKey('history-chosen'),
            initiallyOpen: true,
            searchMode: HistorySearchMode.dedicated,
            columns: 1,
          ),
        ),
        BoardFrame(
          kind: FrameKind.play,
          label: 'Accueil · essayer l’apparition',
          note: 'Clique sur Historique, en bas à droite. La liste apparaît et sa navigation se détache ; la fermeture les rassemble.',
          width: 700,
          child: HistoryTopPreview(
            key: ValueKey('history-home-chosen'),
            searchMode: HistorySearchMode.dedicated,
            columns: 1,
          ),
        ),
      ],
    ),
    const BoardSection(
      title: 'Essais · recherche centrée',
      kind: FrameKind.trial,
      note: 'Recherche détachée et centrée, retour à gauche. Titres 12,5 px, dates 11,5 px, lignes de 40 px : trois rangées au lieu de quatre. Comparaison à une et deux colonnes dans le même format 700 × 200.',
      frames: [
        BoardFrame(
          label: 'Deux colonnes · six conversations',
          note: 'Trois rangées, recherche directe, retour à l’accueil. Tout est cliquable.',
          width: 700,
          child: HistoryTopPreview(key: ValueKey('history-a-two'), initiallyOpen: true),
        ),
        BoardFrame(
          label: 'Une colonne · trois conversations',
          note: 'La même interface en pleine largeur, pour lire davantage du titre de chaque conversation.',
          width: 700,
          child: HistoryTopPreview(key: ValueKey('history-a-one'), initiallyOpen: true, columns: 1),
        ),
      ],
    ),
    const BoardSection(
      title: 'Essais · deux colonnes et recherche',
      kind: FrameKind.trial,
      note: 'La variante à deux colonnes reste comme essai. À côté, la recherche dédiée de la version retenue : saisie immédiate et retour à l’historique à une colonne.',
      frames: [
        BoardFrame(
          label: 'Deux colonnes · huit conversations',
          note: 'Quatre rangées. La navigation détachée reste visible pendant le défilement et la recherche.',
          width: 700,
          child: HistoryTopPreview(
            key: ValueKey('history-b-two'),
            initiallyOpen: true,
            searchMode: HistorySearchMode.dedicated,
          ),
        ),
        BoardFrame(
          label: 'Recherche · version retenue',
          note: 'Saisie immédiate, résultats, puis retour à l’historique. La navigation garde sa place.',
          width: 700,
          child: HistoryTopPreview(
            key: ValueKey('history-search-chosen'),
            initiallyOpen: true,
            searchMode: HistorySearchMode.dedicated,
            initiallySearching: true,
            columns: 1,
          ),
        ),
      ],
    ),
  ],
);

const historyTopSamples = <HistoryRow>[
  HistoryRow(
    id: 'h1',
    title: 'Ajoute la position à droite',
    brand: Brand.claude,
    when: 'Hier',
    status: UiStatus.working,
  ),
  HistoryRow(id: 'h2', title: 'Traduis le README', brand: Brand.codex, when: 'Hier · WSL', status: UiStatus.working),
  HistoryRow(id: 'h3', title: 'Corrige le hook souris', brand: Brand.claude, when: 'Lundi'),
  HistoryRow(id: 'h4', title: 'Prépare la démo de l’île', brand: Brand.claude, when: 'Lundi'),
  HistoryRow(id: 'h5', title: 'Nettoie les imports du moteur', brand: Brand.codex, when: '28 sept.'),
  HistoryRow(id: 'h6', title: 'Écris les tests du lecteur Codex', brand: Brand.codex, when: '28 sept. · WSL'),
  HistoryRow(id: 'h7', title: 'Résume la spec de mikkyd', brand: Brand.claude, when: '27 sept.'),
  HistoryRow(id: 'h8', title: 'Ajoute le menu flottant', brand: Brand.claude, when: '26 sept.'),
  HistoryRow(id: 'h9', title: 'Mesure le CPU de l’île', brand: Brand.codex, when: '25 sept.'),
  HistoryRow(id: 'h10', title: 'Répare la reconnexion du daemon', brand: Brand.codex, when: '24 sept.'),
  HistoryRow(id: 'h11', title: 'Simplifie les permissions Claude', brand: Brand.claude, when: '24 sept. · WSL'),
  HistoryRow(id: 'h12', title: 'Ajoute les raccourcis clavier', brand: Brand.codex, when: '23 sept.'),
  HistoryRow(id: 'h13', title: 'Ajuste les animations de Mikky', brand: Brand.claude, when: '22 sept.'),
  HistoryRow(id: 'h14', title: 'Vérifie les états des messages', brand: Brand.codex, when: '22 sept.'),
  HistoryRow(id: 'h15', title: 'Rends la recherche plus rapide', brand: Brand.claude, when: '21 sept.'),
  HistoryRow(id: 'h16', title: 'Prépare le thème sombre', brand: Brand.claude, when: '20 sept.'),
  HistoryRow(id: 'h17', title: 'Corrige le suivi des sous-agents', brand: Brand.codex, when: '19 sept. · WSL'),
  HistoryRow(id: 'h18', title: 'Nettoie les composants partagés', brand: Brand.codex, when: '18 sept.'),
  HistoryRow(id: 'h19', title: 'Documente le protocole local', brand: Brand.claude, when: '17 sept.'),
  HistoryRow(id: 'h20', title: 'Ajoute les tests des notifications', brand: Brand.codex, when: '16 sept.'),
  HistoryRow(
    id: 'h21',
    title: 'Une conversation au titre particulièrement long pour vérifier la place disponible',
    brand: Brand.claude,
    when: '15 sept.',
  ),
];

/// A live, board-only history page. Closing returns to the real home;
/// its history button reopens the trial. No live sessions are touched.
class HistoryTopPreview extends StatefulWidget {
  const HistoryTopPreview({
    super.key,
    this.initiallyOpen = false,
    this.searchMode = HistorySearchMode.centered,
    this.initiallySearching = false,
    this.columns = 2,
  });

  final bool initiallyOpen;
  final HistorySearchMode searchMode;
  final bool initiallySearching;
  final int columns;

  @override
  State<HistoryTopPreview> createState() => _HistoryTopPreviewState();
}

class _HistoryTopPreviewState extends State<HistoryTopPreview> {
  final _homeKey = GlobalKey();
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show(_homeKey.currentContext!);
      });
    }
  }

  Future<void> _show(BuildContext within) async {
    if (_showing) return;
    _showing = true;
    try {
      await showHistory(
        within,
        rows: historyTopSamples,
        searchMode: widget.searchMode,
        initiallySearching: widget.initiallySearching,
        columns: widget.columns,
        onMenu: (sheet, _) async {
          final choice = await showFloatingMenu(sheet, const [MenuEntry(1, 'Ouvrir')]);
          if (choice == 1 && sheet.mounted) Sheet.close(sheet);
        },
      );
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => HomeFrame(
    layout: HomeLayout.top,
    child: OwnOverlay(
      child: HomeView(key: _homeKey, apps: sampleNotchApps, animate: false, onNew: () {}, onHistory: _show),
    ),
  );
}
