import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../overlay/overlay_channel.dart';
import '../home/tools_rail.dart';
import '../ui/app_tile.dart';
import '../ui/backend_status.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/cards.dart';
import '../ui/feedback.dart';
import '../ui/field.dart';
import '../ui/floating_menu.dart';
import '../ui/motion.dart';
import '../ui/selectors.dart';
import '../ui/side.dart';
import '../ui/sliding_hover.dart';
import '../ui/status.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';
import '../ui/trials/claude_spinner.dart';
import 'board_brand.dart';
import '../home/home_view.dart' show HomeLayout;
import 'board_home.dart';
import 'canvas.dart';

/// A bit of state of its own, so a click rebuilds only its widget.
class Local<T> extends StatefulWidget {
  const Local(this.initial, this.builder, {super.key});

  final T initial;
  final Widget Function(T value, ValueChanged<T> set) builder;

  @override
  State<Local<T>> createState() => _LocalState<T>();
}

class _LocalState<T> extends State<Local<T>> {
  late T _value = widget.initial;

  @override
  Widget build(BuildContext context) => widget.builder(_value, (v) => setState(() => _value = v));
}

Widget _row(List<Widget> children) => Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: children);

/// Components on the window's background, [width] wide.
class _Tray extends StatelessWidget {
  const _Tray(this.children, {this.width = 340});

  final List<Widget> children;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: ui.island, borderRadius: BorderRadius.circular(22), border: Border.all(color: ui.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < children.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 14), child: children[i]),
      ]),
    );
  }
}

/// A button that loads for a moment when pressed.
class _SendButton extends StatefulWidget {
  const _SendButton();

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) => MButton(
    _sending ? 'Envoi…' : 'Envoyer',
    kind: ButtonKind.primary,
    loading: _sending,
    onPressed: () async {
      setState(() => _sending = true);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) setState(() => _sending = false);
    },
  );
}

/// The Composants board (2026-10-02): by category, the most used first, a
/// selector on top whose thumb slides to the category shown. Every
/// component once; one used in several forms shows them side by side,
/// with what each is for.
final componentsBoard = BoardSpec('Composants', 'Par catégorie, les plus utilisés d’abord', (context) => [ComponentsByCategory(categories: _categories(context))]);

/// The categories, in order, and their sections.
List<(String, List<Widget>)> _categories(BuildContext context) {
  final ui = MikkyUi.of(context);
  return [
    ('Boutons', [
      BoardSection(
        title: 'Boutons',
        note: 'Principal : noir (blanc en sombre), un seul par écran. Secondaire : gris en relief. Discret : texte. Rond : une action en icône. Réponses : petits boutons à plat, le carré blanc glisse vers la réponse appuyée.',
        frames: [
          BoardFrame(
            label: 'Ronds',
            note: 'Les plus utilisés : retour, menu (l’étoile grise), envoyer, flèches des pages et historique (28 et 34 px, gris).',
            child: _Tray([
              _row([
                for (final i in ['folder', 'sliders', 'plus']) RoundButton(i, onPressed: () {}),
                RoundButton.menu(size: 40, onPressed: () {}),
                RoundButton('up', ink: true, onPressed: () {}),
              ]),
              _row([
                RoundButton('left', size: 34, onPressed: () {}),
                RoundButton('stop', size: 34, onPressed: () {}),
                RoundButton('x', size: 26, onPressed: () {}),
                RoundButton('go', size: 46, ink: true, onPressed: () {}),
              ]),
              _row([
                RoundButton('left', size: 28, onPressed: () {}),
                RoundButton('right', size: 28, onPressed: () {}),
                RoundButton('history', size: 34, onPressed: () {}),
              ]),
            ]),
          ),
          BoardFrame(
            label: 'Réponses',
            note: 'Oui / Non d’un agent qui attend ; « Toujours » quand l’agent le propose. Toutes les actions d’une ligne ou d’une carte passent par cette barre.',
            child: _Tray([
              AnswerBar(answers: [('Non', () {}), ('Oui', () {})]),
              AnswerBar(answers: [('Toujours', () {}), ('Non', () {}), ('Oui', () {})]),
              AnswerBar(answers: [('Terminer', () {}), ('Relance auto', () {})]),
              WaitActions(command: 'npm run build', onYes: () {}, onNo: () {}),
              WaitActions(command: 'Remove-Item -LiteralPath C:\\essai\\hello.txt', onYes: () {}, onNo: () {}, onAlways: () {}),
            ]),
          ),
          BoardFrame(
            label: 'Capsules',
            note: 'Réservées aux écrans (nouvel agent, connexion, réglages). Normal, petit, désactivé, en cours (clic sur « Envoyer »).',
            child: _Tray([
              _row([
                MButton('Lancer', kind: ButtonKind.primary, onPressed: () {}),
                MButton('Annuler', onPressed: () {}),
                MButton('Plus tard', kind: ButtonKind.ghost, onPressed: () {}),
              ]),
              _row([
                MButton('Lancer', small: true, kind: ButtonKind.primary, onPressed: () {}),
                MButton('Annuler', small: true, onPressed: () {}),
                const MButton('Lancer', small: true, kind: ButtonKind.primary),
              ]),
              const _SendButton(),
            ]),
          ),
        ],
      ),
    ]),
    ('Navigation', [
      BoardSection(
        title: 'Navigation',
        note: 'Ce qui fait passer d’un écran à l’autre.',
        frames: [
          BoardFrame(
            label: 'Modes de l’accueil',
            kind: FrameKind.play,
            note: 'Applications · chat. Le choix en noir (2 octobre) : le seul noir de l’accueil, sa profondeur. 44 px en haut au milieu de l’accueil de droite, 32 dans le notch ; il glisse sur le ressort des sélecteurs, l’icône choisie fait un petit saut.',
            child: BoardPane(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Local(0, (v, set) => MTabBar(mini: true, height: 44, ink: true, selected: v, onChanged: set, items: _modes)),
              ]),
            ),
          ),
          BoardFrame(
            label: 'Le même, en blanc · onglets',
            kind: FrameKind.play,
            note: 'Même composant (`MTabBar`), le carré blanc qui glisse : des onglets dans une page (pour plus tard). Le noir reste à la navigation de l’accueil.',
            child: _Tray([
              Local(0, (v, set) => MTabBar(selected: v, onChanged: set, items: const [
                TabItem('agents', label: 'Agents', dot: true),
                TabItem('share', label: 'Partage'),
                TabItem('mail', label: 'Mails', count: 2),
              ])),
              Local(0, (v, set) => MTabBar(mini: true, selected: v, onChanged: set, items: const [TabItem('agents'), TabItem('share'), TabItem('mail'), TabItem('sliders')])),
            ]),
          ),
          BoardFrame(
            label: 'Pages · l’étoile',
            kind: FrameKind.play,
            note: 'Un petit pixel gris par page, une étoile en pixels sur la page montrée, dans nos bleus signature (un cran plus clairs en sombre). Elle glisse tout droit, très doucement, avec une courte traînée bleue qui s’efface ; la place ne bouge jamais. Clic sur un pixel ; flèches rondes grises, effacées au bout.',
            child: BoardPane(child: Local(0, (page, set) => PagerTry(page: page, set: set))),
          ),
          const BoardFrame(
            label: 'Outils · sortis du bord',
            note: 'Les outils (Claude, Codex) sur un rail sorti du bord de l’écran : plat côté écran, rond vers l’intérieur. Survol : les pastilles s’écartent ; pression : elles rétrécissent. Un clic : un nouvel agent.',
            child: BoardPane(
              edge: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                ToolsRail(onPressed: _nothing),
                SizedBox(height: 16),
                ToolsRail(tools: [Brand.claude, Brand.codex, Brand.opencode], onPressed: _nothing),
              ]),
            ),
          ),
          BoardFrame(
            label: 'En-têtes',
            note: 'Une page d’agent : sans titre, les boutons flottent sur le fil.',
            child: _Tray([
              SizedBox(
                height: 60,
                child: Stack(children: [
                  SideHead(
                    leading: RoundButton('left', size: 34, onPressed: () {}),
                    actions: [RoundButton('stop', size: 34, onPressed: () {}), RoundButton.menu(size: 34, onPressed: () {})],
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ),
    ]),
    ('Sélecteurs', [
      BoardSection(
        title: 'Sélecteurs et champs',
        frames: [
          const BoardFrame(
            label: 'Choisir l’environnement',
            kind: FrameKind.play,
            note: 'Refait le 2 octobre. Le nom en noir et l’étoile grise des réglages, à plat ; gris au survol ; pressé ou menu ouvert, le relief d’une réponse, puis de nouveau à plat dès que le menu part (avant, un contour restait). Le menu sort du sélecteur entier, à sa largeur, et se déroule tout droit (vers le haut en bas de l’accueil). Le nouveau nom monte, l’ancien s’en va par le haut. Contour seulement au clavier. VPS et Cloud dessinés, pas branchés.',
            width: 300,
            child: SelectorTry(),
          ),
          BoardFrame(
            label: 'Sélecteurs',
            kind: FrameKind.play,
            note: 'Le carré glisse avec un ressort (380 / 0,70) ; les autres options foncent au survol.',
            child: _Tray([
              Local(0, (v, set) => Segmented(options: const ['Tous', 'En cours', 'Finis'], selected: v, onChanged: set)),
              Local(0, (v, set) => Segmented(options: const ['Claude', 'Codex'], selected: v, size: SegmentSize.xs, onChanged: set)),
              _row([
                Local(true, (v, set) => MSwitch(value: v, onChanged: set)),
                Local(false, (v, set) => MSwitch(value: v, onChanged: set)),
                Local(true, (v, set) => MChip('Important', count: 2, on: v, onTap: () => set(!v))),
                Local(false, (v, set) => MChip('À répondre', count: 1, on: v, onTap: () => set(!v))),
              ]),
            ]),
          ),
          BoardFrame(
            label: 'Le carré qui glisse',
            kind: FrameKind.play,
            note: 'Le survol et le choix de Mikky. Sur fond gris, le carré blanc marque le choix et glisse au clic ; au survol, le nom s’éclaire (colonne des planches, menus). Dans une liste sans choix, il suit la souris.',
            child: Container(
              width: 260,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: ui.well, borderRadius: BorderRadius.circular(22), border: Border.all(color: ui.line)),
              child: Local(1, (picked, set) => SlidingHover(
                radius: 12,
                followHover: false,
                hairline: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, t) in ['Marque', 'Composants', 'Accueil', 'Agent'].indexed)
                    HoverTarget(
                      selected: i == picked,
                      child: HoverBuilder(
                        builder: (context, hover) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => set(i),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            child: Text(t, style: uiText(TextSize.body, weight: i == picked ? FontWeight.w600 : FontWeight.w500, color: i == picked || hover ? ui.text : ui.text3)),
                          ),
                        ),
                      ),
                    ),
                ]),
              )),
            ),
          ),
          BoardFrame(
            label: 'Champ de saisie',
            note: 'Grandit jusqu’à 5 lignes ; les options à moitié dedans : dossier et modèle pour une nouvelle tâche ; rien pour écrire à un agent.',
            child: _Tray([
              Composer(
                placeholder: 'Que doit faire l’agent ?',
                options: Row(mainAxisSize: MainAxisSize.min, children: [
                  ComposerChip('mikky', icon: 'folder', onTap: () {}),
                  const SizedBox(width: 6),
                  ComposerChip('Claude · Opus', leading: const BrandLogo(Brand.claude, size: 12), onTap: () {}),
                ]),
              ),
              const SizedBox(height: 4),
              const Composer(placeholder: 'Écris à cet agent…'),
            ]),
          ),
          BoardFrame(
            label: 'Champs',
            child: _Tray([
              const SearchField(icon: 'search', placeholder: 'Chercher une session, un fichier…'),
              SearchField(placeholder: 'Nom du projet', controller: TextEditingController(text: 'mikky')),
            ]),
          ),
        ],
      ),
    ]),
    ('Applications', [
      BoardSection(
        title: 'Applications',
        note: 'Une application : un ou plusieurs agents qui font une tâche. Des tuiles, un seul arrondi pour toutes les tailles (27 % du côté), le bord clair et le trait fin de nos contrôles en relief ; au survol elles montent de 2 px, à la pression elles rétrécissent. Leur dessin viendra.',
        frames: [
          BoardFrame(
            label: 'Tuiles',
            note: 'Carrées, 64 px, 8 par page : l’accueil de droite. Larges, 160 × 42 : le notch (le signe du logiciel, le titre, une ligne qui change ; planche Notch Top). Neutres tant qu’elles n’ont pas leur dessin.',
            child: BoardPane(
              width: 300,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                AppTile(size: 64, label: 'Application', onTap: _nothing),
                const SizedBox(width: 24),
                AppTile(size: 42, width: 160, label: 'Application', onTap: _nothing),
              ]),
            ),
          ),
          BoardFrame(
            label: 'À droite, dans l’app',
            note: 'En attendant leur dessin : le logo de l’outil et l’état de l’agent au coin (nos feux d’artifice, petits) ; rien en pause. Ceux qui attendent, travaillent et les derniers terminés ; pas l’historique.',
            child: BoardPane(
              width: 340,
              child: Row(children: [
                for (final a in sampleApps.take(4)) ...[
                  AppTile(size: 56, status: a.status, onTap: _nothing, child: Center(child: BrandLogo(a.brand!, size: 19))),
                  const SizedBox(width: 16),
                ],
              ]),
            ),
          ),
          const BoardFrame(
            label: 'Commencer une tâche, places libres',
            note: 'Après les applications, la première place libre devient « + » (une nouvelle tâche) ; les autres gardent un petit jeton creusé au milieu, qui attend une application. Une page est toujours pleine.',
            child: BoardPane(
              width: 360,
              child: Row(children: [
                AddTile(size: 64, onTap: _nothing),
                SizedBox(width: 16),
                AppSlot(size: 64),
                SizedBox(width: 16),
                AppSlot(size: 64),
                SizedBox(width: 16),
                AppSlot(size: 64),
              ]),
            ),
          ),
          const BoardFrame(
            label: 'Mikky',
            note: 'Le vrai Mikky, vivant : il cligne, regarde autour, prend l’état de l’agent qu’il suit. 72 px en haut à gauche de l’accueil de droite, 96 à gauche du notch (120 quand rien ne tourne), sans case. Au repos, au travail, fini.',
            child: BoardPane(
              width: 270,
              child: Row(children: [
                MiniMikky(size: 72, badge: false),
                MiniMikky(size: 72, badge: false, state: MikkyState.working),
                MiniMikky(size: 72, badge: false, state: MikkyState.finished),
              ]),
            ),
          ),
        ],
      ),
    ]),
    ('Historique', [
      const BoardSection(
        title: 'Historique',
        note: 'Un composant : `showHistory`, sur notre feuille par-dessus (`showSheet`). Le bouton Historique, en bas à gauche, l’ouvre : l’accueil derrière s’assombrit et se floute un peu ; la feuille monte au milieu sur un ressort doux — 316 de large au plus, les deux tiers de la fenêtre à droite, presque toute la hauteur du notch en haut. En-tête léger (titre, nombre, petit ×), une barre de recherche (elle ne regarde pour l’instant que les titres), puis l’historique comme avant : les lignes, la petite étoile grise. Un clic ferme la feuille et ouvre l’agent, qui revient parmi les applications ; un clic dans le sombre, Échap ou × la referme.',
        frames: [
          BoardFrame(kind: FrameKind.play, label: 'À droite · à essayer', note: 'Le bouton en bas à gauche.', width: 290, child: HistoryTry()),
          BoardFrame(label: 'À droite · ouvert', width: 290, child: HistoryOpen()),
          BoardFrame(kind: FrameKind.play, label: 'Notch · à essayer', width: 700, child: HistoryTry(layout: HomeLayout.top)),
          BoardFrame(label: 'Notch · ouvert', width: 700, child: HistoryOpen(layout: HomeLayout.top)),
        ],
      ),
    ]),
    ('Menus', [
      const BoardSection(
        title: 'Menu flottant',
        note: 'Notre menu, à la place de celui de Windows : panneau gris clair, le carré blanc qui glisse sous l’option survolée, une coche pour ce qui est actif, en rouge ce qui ne se défait pas. Il sort de l’étoile grise ; Échap ou un clic à côté le replie dedans.',
        frames: [
          BoardFrame(kind: FrameKind.play, label: 'À essayer', note: 'Clique sur l’étoile grise : le menu se déploie et se replie en elle (une seule étoile à la fois).', width: 300, child: _MenuTry(_homeMenu)),
          BoardFrame(
            label: 'À essayer · Supprimer…',
            kind: FrameKind.play,
            note: 'Un menu qui en ouvre un autre : le panneau ne se replie pas, il prend sur place la taille de la confirmation.',
            width: 300,
            child: _MenuTry(_agentMenu, followUps: {7: _deleteMenu}),
          ),
          BoardFrame(label: 'Réglages · étoile grise', note: 'Les réglages de Mikky (clic droit sur l’île).', width: 264, child: FloatingMenuPanel(entries: _homeMenu)),
          BoardFrame(label: 'Un agent · étoile grise', note: 'Ce qu’on fait de lui.', width: 264, child: FloatingMenuPanel(entries: _agentMenu)),
        ],
      ),
    ]),
    ('Retours', [
      BoardSection(
        title: 'Retours et notifications',
        frames: [
          BoardFrame(
            label: 'États d’un agent',
            note: 'Le feu d’artifice bleu pour tout le travail, « ! » pour ce qui attend ton feu vert ou ta réponse, « ! » rouge pour une erreur, le jaune pour la limite, le vert figé quand c’est fini ; rien en pause. Le violet est réservé à « Ensorcelé ».',
            child: _Tray([
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (s, name) in [
                  (UiStatus.working, 'Travaille'),
                  (UiStatus.approval, 'Attend'),
                  (UiStatus.error, 'Erreur'),
                  (UiStatus.limited, 'Limite'),
                  (UiStatus.finished, 'Terminé'),
                  (UiStatus.paused, 'En pause (rien)'),
                ])
                  SizedBox(
                    width: 140,
                    child: Row(children: [StatusDot(s), const SizedBox(width: 6), Text(name, style: uiText(TextSize.label, weight: FontWeight.w500, color: ui.text))]),
                  ),
              ]),
            ]),
          ),
          BoardFrame(
            label: 'Notifications',
            note: 'Un message qui arrive (toast) ; l’état du moteur, en haut de la fenêtre quand il manque.',
            child: _Tray([
              Toast(icon: 'file', title: 'IMG_2041.jpg reçue', subtitle: 'De Téléphone · rangée dans Téléchargements', action: MButton('Ouvrir', small: true, onPressed: () {})),
              const SizedBox(width: 328, child: BackendStatus(title: 'Reconnexion en cours', message: 'Le dernier état reste visible.')),
            ], width: 360),
          ),
          BoardFrame(
            label: 'Attente, progrès, pastilles',
            child: _Tray([
              const ProgressBar(value: .4),
              const ProgressBar(),
              _row([
                const Spinner(),
                const TypingDots(),
                Stack(clipBehavior: Clip.none, children: [RoundButton('mail', onPressed: () {}), Positioned(top: -4, right: -6, child: CountBadge(2, ring: ui.board))]),
                Stack(clipBehavior: Clip.none, children: [RoundButton('agents', onPressed: () {}), Positioned(top: 0, right: 0, child: DotBadge(ring: ui.board))]),
                const CodePill('npm run build'),
              ]),
            ]),
          ),
        ],
      ),
    ]),
    ('Couleurs', [interfaceColorsSection(ui)]),
    ('Essais', [
      BoardSection(
        title: 'Essais et à faire',
        kind: FrameKind.trial,
        frames: [
          BoardFrame(
            label: 'Claude au travail : deux essais',
            note: 'À gauche, son logo qui tourne et respire (dans l’app). À droite, l’étoile de Claude Code, comme dans son terminal.',
            child: _Tray([
              Row(children: [
                const SizedBox(width: 34, child: Center(child: SpinningLogo(claude: true, child: BrandLogo(Brand.claude, size: 32)))),
                const SizedBox(width: 40),
                const SizedBox(width: 34, child: Center(child: ClaudeSpinner(size: 30))),
                const SizedBox(width: 12),
                Text('Pondering…', style: uiText(TextSize.label, color: const Color(0xFFD97757), weight: FontWeight.w500)),
              ]),
            ], width: 300),
          ),
          BoardFrame(
            label: 'Composants qui manquent',
            width: 520,
            child: SizedBox(
              width: 520,
              child: Text(
                '• Le dessin des applications, et leurs actions rapides (Oui / Non, limite…).\n'
                '• Infobulle.\n'
                '• Boîte de confirmation (aujourd’hui un menu qui redemande).\n'
                '• Notification d’erreur (toast rouge).\n'
                '• Écran de connexion et écran de réglages.',
                style: uiText(TextSize.label, color: ui.text2, height: 1.55),
              ),
            ),
          ),
        ],
      ),
    ]),
  ];
}

const _modes = [TabItem('grid', label: 'Applications'), TabItem('chat', label: 'Chat')];

void _nothing() {}

/// The board's categories: a selector (its thumb slides to the one shown),
/// then their sections, « Tout » by default.
class ComponentsByCategory extends StatefulWidget {
  const ComponentsByCategory({super.key, required this.categories});

  final List<(String, List<Widget>)> categories;

  @override
  State<ComponentsByCategory> createState() => _ComponentsByCategoryState();
}

class _ComponentsByCategoryState extends State<ComponentsByCategory> {
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final names = ['Tout', for (final (name, _) in widget.categories) name];
    final sections = [
      for (final (i, (_, list)) in widget.categories.indexed)
        if (_shown == 0 || _shown == i + 1) ...list,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Segmented(options: names, selected: _shown, onChanged: (i) => setState(() => _shown = i)),
        const SizedBox(height: 8),
        Text('Les plus utilisés d’abord. Choisis une catégorie : le carré glisse, la planche n’en montre que les composants.', style: uiText(TextSize.small, color: ui.text3)),
        const SizedBox(height: 40),
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.fade),
          switchInCurve: Motion.enter,
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
          child: Column(key: ValueKey(_shown), crossAxisAlignment: CrossAxisAlignment.start, children: sections),
        ),
      ],
    );
  }
}

const _homeMenu = [
  MenuEntry(1, 'Thème : automatique', checked: true),
  MenuEntry(2, 'Thème : noir'),
  MenuEntry(3, 'Thème : blanc'),
  MenuEntry.separator(),
  MenuEntry(4, 'En haut'),
  MenuEntry(5, 'À droite', checked: true),
  MenuEntry.separator(),
  MenuEntry(6, 'Notifications', checked: true),
  MenuEntry(7, 'Relance automatique', checked: true),
  MenuEntry(8, 'Réglage de Mikky…'),
  MenuEntry.separator(),
  MenuEntry(9, 'Arrêter tous les agents de Mikky…'),
  MenuEntry(10, 'Fermer Mikky · les agents continuent'),
];

const _agentMenu = [
  MenuEntry(1, 'Ouvrir dans VS Code'),
  MenuEntry(2, 'Ouvrir le dossier'),
  MenuEntry.separator(),
  MenuEntry(3, 'Arrêter la relance auto'),
  MenuEntry(4, 'Renommer…'),
  MenuEntry(5, 'Épingler'),
  MenuEntry(6, 'Archiver'),
  MenuEntry.separator(),
  MenuEntry(7, 'Supprimer…'),
];

/// « Supprimer… » asks again.
const _deleteMenu = [
  MenuEntry(20, 'Supprimer de Mikky (le fichier de session reste)'),
  MenuEntry(21, 'Supprimer aussi le fichier de Claude (définitif)'),
  MenuEntry.separator(),
  MenuEntry(22, 'Annuler'),
];

/// A small window with its grey star: the real menu opens in it; a choice
/// in [followUps] opens the next one, as the app does.
class _MenuTry extends StatefulWidget {
  const _MenuTry(this.entries, {this.followUps = const {}});

  final List<MenuEntry> entries;
  final Map<int, List<MenuEntry>> followUps;

  @override
  State<_MenuTry> createState() => _MenuTryState();
}

class _MenuTryState extends State<_MenuTry> {
  String? _chosen;

  // The boards have no overlay of their own: this little window brings one
  // (the app's has it).
  late final _layer = OverlayEntry(builder: _window);

  @override
  void initState() {
    super.initState();
    FloatingMenu.track();
  }

  Widget _window(BuildContext inner) {
    final ui = MikkyUi.of(inner);
    return Stack(children: [
      Positioned(
        top: 14,
        right: 14,
        child: RoundButton.menu(size: 34, onPressed: () async {
          var entries = widget.entries;
          var id = await showFloatingMenu(inner, entries);
          while (id != null) {
            final next = widget.followUps[id];
            if (next == null || !inner.mounted) break;
            entries = next;
            id = await showFloatingMenu(inner, entries);
          }
          if (!mounted) return;
          final chosen = id;
          setState(() => _chosen = chosen == null ? 'rien' : entries.firstWhere((e) => e.id == chosen).label);
          _layer.markNeedsBuild();
        }),
      ),
      Positioned(
        left: 18,
        bottom: 16,
        right: 18,
        child: Text(_chosen == null ? 'Rien choisi' : 'Choisi : $_chosen', style: uiText(TextSize.small, color: ui.text3)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: 300,
      height: 460,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: ui.island, borderRadius: BorderRadius.circular(22), border: Border.all(color: ui.line)),
      child: Overlay(initialEntries: [_layer]),
    );
  }
}
