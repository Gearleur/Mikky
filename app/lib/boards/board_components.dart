import 'package:flutter/widgets.dart';

import '../overlay/overlay_channel.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/cards.dart';
import '../ui/feedback.dart';
import '../ui/field.dart';
import '../ui/floating_menu.dart';
import '../ui/metro.dart';
import '../ui/motion.dart';
import '../ui/selectors.dart';
import '../ui/side.dart';
import '../ui/sliding_hover.dart';
import '../ui/status.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';
import '../ui/trials/claude_spinner.dart';
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

final componentsBoard = BoardSpec('Composants', 'Chaque composant une fois, avec ses états', (context) {
  final ui = MikkyUi.of(context);
  return [
    BoardSection(
      title: 'Boutons',
      note: 'Principal : noir (blanc en sombre), un seul par écran. Secondaire : gris en relief. Discret : texte. Rond : une action en icône. Réponses : petits boutons à plat, le carré blanc glisse vers la réponse appuyée.',
      frames: [
        BoardFrame(
          label: 'Capsules',
          note: 'Normal, petit, désactivé, en cours (clic sur « Envoyer »).',
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
        BoardFrame(
          label: 'Ronds',
          child: _Tray([
            _row([
              for (final i in ['folder', 'sliders', 'plus', 'more']) RoundButton(i, onPressed: () {}),
              RoundButton('up', ink: true, onPressed: () {}),
            ]),
            _row([
              RoundButton('left', size: 34, onPressed: () {}),
              RoundButton('stop', size: 34, onPressed: () {}),
              RoundButton('x', size: 26, onPressed: () {}),
              RoundButton('go', size: 46, ink: true, onPressed: () {}),
            ]),
          ]),
        ),
        BoardFrame(
          label: 'Réponses',
          note: 'Oui / Non d’un agent qui attend ; « Toujours » quand l’agent le propose.',
          child: _Tray([
            AnswerBar(answers: [('Non', () {}), ('Oui', () {})]),
            AnswerBar(answers: [('Toujours', () {}), ('Non', () {}), ('Oui', () {})]),
            WaitActions(command: 'npm run build', onYes: () {}, onNo: () {}),
            WaitActions(command: 'Remove-Item -LiteralPath C:\\essai\\hello.txt', onYes: () {}, onNo: () {}, onAlways: () {}),
          ]),
        ),
      ],
    ),
    BoardSection(
      title: 'Sélecteurs et champs',
      frames: [
        BoardFrame(
          label: 'Sélecteurs',
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
          label: 'Champs',
          child: _Tray([
            const SearchField(icon: 'search', placeholder: 'Chercher une session, un fichier…'),
            SearchField(placeholder: 'Nom du projet', controller: TextEditingController(text: 'mikky')),
          ]),
        ),
        BoardFrame(
          label: 'Champ de saisie',
          note: 'Grandit jusqu’à 5 lignes ; les options à moitié dedans : dossier et modèle, ou Suivi | Chat.',
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
            Local(0, (v, set) => Composer(
              placeholder: 'Écris à cet agent…',
              options: Segmented(options: const ['Suivi', 'Chat'], selected: v, size: SegmentSize.field, onChanged: set),
            )),
          ]),
        ),
      ],
    ),
    BoardSection(
      title: 'Menu flottant',
      note: 'Notre menu, à la place de celui de Windows : panneau gris clair, le carré blanc qui glisse sous l’option survolée, une coche pour ce qui est actif, en rouge ce qui ne se défait pas. Il s’ouvre là où on a cliqué ; Échap ou un clic à côté le ferme.',
      frames: [
        const BoardFrame(label: 'Accueil ···', note: 'Les réglages de Mikky.', width: 264, child: FloatingMenuPanel(entries: _homeMenu)),
        const BoardFrame(label: 'Un agent ···', note: 'Ce qu’on fait de lui.', width: 264, child: FloatingMenuPanel(entries: _agentMenu)),
        const BoardFrame(label: 'À essayer', note: 'Clique sur ··· : le vrai menu s’ouvre.', width: 300, child: _MenuTry()),
      ],
    ),
    BoardSection(
      title: 'Navigation',
      frames: [
        BoardFrame(
          label: 'En-têtes',
          note: 'L’accueil avec Mikky ; une page d’agent : sans titre, les boutons flottent sur le fil.',
          child: _Tray([
            SizedBox(
              height: 60,
              child: Stack(children: [SideHead(title: 'Agents', leading: const HeadMikky(), actions: [RoundButton('more', size: 34, onPressed: () {})])]),
            ),
            SizedBox(
              height: 60,
              child: Stack(children: [
                SideHead(
                  leading: RoundButton('left', size: 34, onPressed: () {}),
                  actions: [RoundButton('stop', size: 34, onPressed: () {}), RoundButton('more', size: 34, onPressed: () {})],
                ),
              ]),
            ),
          ]),
        ),
        BoardFrame(
          label: 'Onglets (pour plus tard)',
          child: _Tray([
            Local(0, (v, set) => MTabBar(selected: v, onChanged: set, items: const [
              TabItem('agents', label: 'Agents', dot: true),
              TabItem('share', label: 'Partage'),
              TabItem('mail', label: 'Mails', count: 2),
            ])),
            Local(0, (v, set) => MTabBar(mini: true, selected: v, onChanged: set, items: const [TabItem('agents'), TabItem('share'), TabItem('mail'), TabItem('sliders')])),
          ]),
        ),
      ],
    ),
    BoardSection(
      title: 'Lignes de l’accueil',
      note: 'Pas de cartes : des lignes. Au survol, le carré blanc de Oui / Non glisse sous la ligne (ressort des sélecteurs) et revient sur la ligne choisie. Le logo de l’outil à gauche ; il tourne pendant le travail, sautille quand l’agent attend.',
      frames: [
        BoardFrame(
          label: 'Titres de groupes',
          child: _Tray([
            GroupHeader(label: 'En attente', color: ui.amber, status: UiStatus.approval, count: 1, first: true, onTap: () {}),
            GroupHeader(label: 'Travaillent', color: ui.blue, status: UiStatus.working, count: 2, onTap: () {}),
            GroupHeader(label: 'Terminés', color: ui.green, status: UiStatus.finished, count: 3, onTap: () {}),
            GroupHeader(label: 'Historique', color: ui.grey, count: 12, open: false, onTap: () {}),
          ]),
        ),
        BoardFrame(
          label: 'Indicateur : le carré qui glisse',
          note: 'Sur fond gris, le carré blanc marque le choix et glisse au clic ; au survol, le nom s’éclaire (colonne des planches). Dans une liste sans choix (accueil, étapes), le carré suit la souris.',
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
          label: 'Claude au travail : deux essais',
          note: 'À gauche, son logo qui tourne et respire (dans l’app). À droite, l’étoile de Claude Code, comme dans son terminal : point, croix, astérisque, étoile, fleur, et retour.',
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
          label: 'Agents',
          child: _Tray([
            SlidingHover(
              radius: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AgentCard(
              status: UiStatus.approval,
              title: 'Met à jour le site',
              who: 'WSL',
              brand: Brand.codex,
              subtitle: 'Veut lancer une commande',
              style: AgentCardStyle.waiting,
              onTap: () {},
              actions: WaitActions(command: 'npm run build', onYes: () {}, onNo: () {}),
            ),
            AgentCard(status: UiStatus.working, title: 'Corrige les tests du moteur', who: '', brand: Brand.claude, subtitle: 'Modifie island_machine.dart', onTap: () {}),
            AgentCard(status: UiStatus.thinking, title: 'Prépare le plan de l’API', who: '', brand: Brand.codex, subtitle: 'Réfléchit au plan', pinned: true, onTap: () {}),
            AgentCard(status: UiStatus.finished, title: 'Résume la spec', who: '', brand: Brand.claude, subtitle: 'Il y a 2 min', style: AgentCardStyle.done, onTap: () {}),
            AgentCard(status: UiStatus.finished, title: 'Traduis le README', who: 'Codex', style: AgentCardStyle.old, onTap: () {}),
              ]),
            ),
          ], width: 320),
        ),
      ],
    ),
    BoardSection(
      title: 'Retours',
      frames: [
        BoardFrame(
          label: 'États d’un agent',
          note: 'Un feu d’artifice de pixels par état, à son rythme.',
          child: _Tray([
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (s, name) in [
                (UiStatus.working, 'Travaille'),
                (UiStatus.thinking, 'Réfléchit'),
                (UiStatus.approval, 'Attend'),
                (UiStatus.finished, 'Terminé'),
                (UiStatus.error, 'Erreur'),
                (UiStatus.limited, 'Limité'),
                (UiStatus.sleeping, 'Dort'),
              ])
                SizedBox(
                  width: 140,
                  child: Row(children: [StatusDot(s), const SizedBox(width: 6), Text(name, style: uiText(TextSize.label, weight: FontWeight.w500, color: ui.text))]),
                ),
            ]),
          ]),
        ),
        BoardFrame(
          label: 'Attente, progrès, pastilles',
          child: _Tray([
            Toast(icon: 'file', title: 'IMG_2041.jpg reçue', subtitle: 'De Téléphone · rangée dans Téléchargements', action: MButton('Ouvrir', small: true, onPressed: () {})),
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
        BoardFrame(
          label: 'Suivi',
          note: 'La ligne de métro : fait, en cours (trait bleu qui avance), à faire, message glissé.',
          child: const _Tray([
            MetroStep(kind: StepKind.done, past: true, first: true, child: Text('Lancer les tests')),
            MetroStep(kind: StepKind.me, past: true, meta: '14:02', child: Text('Regarde aussi le délai')),
            MetroStep(kind: StepKind.now, child: Text('Corriger la fermeture auto')),
            MetroStep(kind: StepKind.todo, child: Text('Relancer les tests')),
            MetroStep(kind: StepKind.todo, last: true, child: Text('Terminé')),
          ], width: 320),
        ),
      ],
    ),
    BoardSection(
      title: 'Retirés et à faire',
      frames: [
        BoardFrame(
          label: 'Doublons retirés des planches',
          width: 520,
          child: SizedBox(
            width: 520,
            child: Text(
              '• Les petits boutons Oui / Non en relief : remplacés par les Réponses à plat.\n'
              '• La barre de titre flottante « Réglages » : c’est l’en-tête des pages.\n'
              '• La barre d’actions « Envoyer à Téléphone » : pour LocalSend, plus tard.\n'
              '• Les carrés d’état, le lanceur, les points d’état ronds : remplacés par les feux d’artifice.',
              style: uiText(TextSize.label, color: ui.text2, height: 1.55),
            ),
          ),
        ),
        BoardFrame(
          label: 'Composants qui manquent',
          width: 520,
          child: SizedBox(
            width: 520,
            child: Text(
              '• Menu déroulant à nos couleurs (agent, modèle, dossier, clic droit sur une session) : aujourd’hui le menu de Windows.\n'
              '• Infobulle.\n'
              '• Boîte de confirmation (supprimer une session) : aujourd’hui celle de Windows.\n'
              '• Notification d’erreur (toast rouge) et état vide d’une page.\n'
              '• Écran de connexion et écran de réglages sur les planches.',
              style: uiText(TextSize.label, color: ui.text2, height: 1.55),
            ),
          ),
        ),
      ],
    ),
  ];
});

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

/// A small window with its ··· button: the real menu opens in it.
class _MenuTry extends StatefulWidget {
  const _MenuTry();

  @override
  State<_MenuTry> createState() => _MenuTryState();
}

class _MenuTryState extends State<_MenuTry> {
  String? _chosen;
  final _button = GlobalKey();

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
        child: RoundButton('more', key: _button, size: 34, onPressed: () async {
          final box = _button.currentContext!.findRenderObject() as RenderBox;
          final id = await showFloatingMenu(inner, _homeMenu, from: box.localToGlobal(Offset.zero) & box.size);
          if (!mounted) return;
          setState(() => _chosen = id == null ? 'rien' : _homeMenu.firstWhere((e) => e.id == id).label);
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
