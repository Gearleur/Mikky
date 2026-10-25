import '../home/home_frame.dart';
import '../home/home_layout.dart';
import '../home/home_view.dart';
import '../ui/content/history_view.dart';
import '../ui/foundation/tokens.dart';
import 'board_components_history.dart';
import 'board_notch.dart' show sampleNotchApps;
import 'board_settings_top.dart';
import 'canvas.dart';

/// The installed palette on the actual screens, without alternate themes.
BoardSection appliedThemeSection(MikkyUi ui) => BoardSection(
  title: 'Thème appliqué · accueil, historique, paramètres',
  note: ui.isLight ? 'Le thème clair garde ses couleurs. Les mêmes composants utilisent les jetons du thème choisi.' : 'Noir doux #171717 · applications gris sélecteur #2C2C30. Fonds communs dans toute l’app ; boutons et états conservés.',
  frames: [
    BoardFrame(
      label: 'Accueil',
      width: 700,
      child: HomeFrame(
        layout: HomeLayout.top,
        child: HomeView(apps: sampleNotchApps, animate: false, onOpen: (_) {}, onNew: () {}),
      ),
    ),
    const BoardFrame(
      label: 'Historique',
      width: 700,
      child: HistoryTopPreview(initiallyOpen: true, columns: 1, searchMode: HistorySearchMode.dedicated),
    ),
    const BoardFrame(label: 'Paramètres', width: 700, child: SettingsTopPreview(initiallyOpen: true)),
  ],
);
