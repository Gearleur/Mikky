import 'package:flutter/widgets.dart';

import 'brand_logo.dart';
import 'buttons.dart';
import 'cards.dart';
import 'feedback.dart';
import 'pixel_fx.dart';
import 'field.dart';
import 'icons.dart';
import 'selectors.dart';
import 'side.dart';
import 'surface.dart';
import 'tabs.dart';
import 'thread.dart';
import 'tokens.dart';

/// `mikky.exe --kit`: every component of the small window, light and dark,
/// to compare with `design/prototypes/composants.html` and `ux-a.html`.
/// Development tool, like the tuning screen.
class KitApp extends StatelessWidget {
  const KitApp({super.key, this.performance = false});

  /// `--perf`: Flutter's frame graphs on top (build and raster times).
  final bool performance;

  @override
  Widget build(BuildContext context) => WidgetsApp(
    title: 'Composants de Mikky',
    color: MikkyUi.light.board,
    debugShowCheckedModeBanner: false,
    showPerformanceOverlay: performance,
    builder: (context, _) => ColoredBox(
      color: MikkyUi.light.board,
      child: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitBoard(ui: MikkyUi.light),
            KitBoard(ui: MikkyUi.dark),
          ],
        ),
      ),
    ),
  );
}

/// One board (`.board`): the home and an agent's page in their window,
/// then the kit.
class KitBoard extends StatelessWidget {
  const KitBoard({super.key, required this.ui});

  final MikkyUi ui;

  @override
  Widget build(BuildContext context) => MikkyUiTheme(
    ui: ui,
    child: ColoredBox(
      color: ui.board,
      child: DefaultTextStyle(
        style: uiText(15, color: ui.text),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 34, 40, 56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    ui.isLight ? 'Clair' : 'Sombre',
                    style: uiText(17, weight: FontWeight.w600, color: ui.text),
                  ),
                  const SizedBox(width: 10),
                  Text(ui.isLight ? 'avec l’île blanc pur' : 'avec l’île noir A', style: uiText(13, color: ui.text2)),
                ],
              ),
              const SizedBox(height: 26),
              const Wrap(
                spacing: 44,
                runSpacing: 44,
                children: [
                  KitHome(),
                  KitAgent(),
                  SizedBox(width: 440, child: KitParts()),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The home of `ux-a.html`, with sample agents.
class KitHome extends StatefulWidget {
  const KitHome({super.key});

  @override
  State<KitHome> createState() => _KitHomeState();
}

class _KitHomeState extends State<KitHome> {
  final _open = {'wait': true, 'work': true, 'done': true, 'old': false};

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    Widget group(String id, String label, Color color, int n, List<Widget> cards, {bool first = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupHeader(
          label: label,
          color: color,
          count: n,
          open: _open[id]!,
          first: first,
          status: switch (id) {
            'wait' => UiStatus.approval,
            'work' => UiStatus.working,
            'done' => UiStatus.finished,
            _ => null,
          },
          onTap: () => setState(() => _open[id] = !_open[id]!),
        ),
        if (_open[id]!)
          for (var i = 0; i < cards.length; i++)
            Padding(
              padding: EdgeInsets.zero,
              child: cards[i],
            ),
      ],
    );
    return SideFrame(
      child: Stack(
        children: [
          SideHead(
            title: 'Agents',
            leading: const HeadMikky(),
            actions: [RoundButton('more', size: 34, onPressed: () {})],
          ),
          Positioned.fill(
            top: 68,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  group('wait', 'En attente', ui.amber, 1, first: true, [
                    AgentCard(
                      status: UiStatus.approval,
                      title: 'Met à jour le site',
                      who: 'WSL',
                      brand: Brand.codex,
                      subtitle: 'Veut lancer une commande',
                      style: AgentCardStyle.waiting,
                      actions: WaitActions(command: 'npm run build', onYes: () {}, onNo: () {}),
                    ),
                  ]),
                  group('work', 'Travaillent', ui.blue, 2, [
                    AgentCard(
                      status: UiStatus.working,
                      title: 'Corrige les tests du moteur',
                      who: '',
                      brand: Brand.claude,
                      subtitle: 'Modifie island_machine.dart',
                      onTap: () {},
                    ),
                    AgentCard(
                      status: UiStatus.thinking,
                      title: 'Prépare le plan de l’API',
                      who: '',
                      brand: Brand.codex,
                      subtitle: 'Réfléchit au plan',
                      onTap: () {},
                    ),
                  ]),
                  group('done', 'Terminés', ui.green, 3, [
                    for (final (t, b, ago, w) in [
                      ('Résume la spec', Brand.claude, 'Il y a 2 min', ''),
                      ('Ajoute les tests du lecteur Codex', Brand.codex, 'Il y a 14 min', 'WSL'),
                      ('Corrige le clic en dehors', Brand.claude, 'Il y a 1 h', ''),
                    ])
                      AgentCard(status: UiStatus.finished, title: t, who: w, brand: b, subtitle: ago, style: AgentCardStyle.done, onTap: () {}),
                  ]),
                  group('old', 'Historique', ui.grey, 12, [
                    for (final (t, w) in [
                      ('Ajoute la position à droite', 'Claude'),
                      ('Traduis le README', 'Codex'),
                      ('Corrige le hook souris', 'Claude'),
                    ])
                      AgentCard(status: UiStatus.finished, title: t, who: w, style: AgentCardStyle.old, onTap: () {}),
                  ]),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: RoundButton('go', size: 46, ink: true, onPressed: () {}, tooltip: 'Nouvel agent'),
          ),
        ],
      ),
    );
  }
}

/// An agent at work (`ux-a.html`, « Agent au travail : Suivi »).
class KitAgent extends StatefulWidget {
  const KitAgent({super.key});

  @override
  State<KitAgent> createState() => _KitAgentState();
}

class _KitAgentState extends State<KitAgent> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final k = TextStyle(color: ui.purple), m = TextStyle(color: ui.amber), f = TextStyle(color: ui.blue);
    final suivi = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Modifie island_machine.dart',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiText(14.5, weight: FontWeight.w600, color: ui.text),
                ),
              ),
              const SizedBox(width: 10),
              Text('3 sur 5', style: uiText(12, color: ui.text2, tabular: true)),
            ],
          ),
        ),
        const MetroStep(kind: StepKind.done, past: true, first: true, child: Text('Lire la spec et les tests')),
        MetroStep(
          kind: StepKind.done,
          past: true,
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Lancer les tests · '),
                TextSpan(
                  text: '2 échecs',
                  style: TextStyle(color: ui.red, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        const MetroStep(kind: StepKind.me, past: true, meta: '9:40', child: Text('Garde 45 s, pas 30')),
        const MetroStep(kind: StepKind.it, past: true, child: Text('Ok, 45 s.')),
        MetroStep(
          kind: StepKind.now,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Corriger la fermeture auto'),
              const SizedBox(height: 8),
              DefaultTextStyle.merge(
                style: const TextStyle(fontWeight: FontWeight.w400),
                child: CodeCard(
                  file: 'island_machine.dart',
                  lines: [
                    CodeLine(12, [
                      TextSpan(text: 'const', style: k),
                      const TextSpan(text: ' autoCloseSec = '),
                      TextSpan(text: '60', style: m),
                      const TextSpan(text: ';'),
                    ], removed: true),
                    CodeLine(12, [
                      TextSpan(text: 'const', style: k),
                      const TextSpan(text: ' autoCloseSec = '),
                      TextSpan(text: '45', style: m),
                      const TextSpan(text: ';'),
                    ], added: true),
                    const CodeLine(13, []),
                    CodeLine(14, [
                      TextSpan(text: 'bool', style: k),
                      const TextSpan(text: ' '),
                      TextSpan(text: 'closes', style: f),
                      const TextSpan(text: '('),
                      TextSpan(text: 'int', style: k),
                      const TextSpan(text: ' idle) =>'),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        const MetroStep(kind: StepKind.todo, child: Text('Relancer les tests')),
        const MetroStep(kind: StepKind.todo, last: true, child: Text('Terminé')),
      ],
    );
    final chat = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ChatMessage(me: true, text: 'Tu peux regarder pourquoi les tests du moteur cassent ?', meta: '9:30 · mikky · Claude'),
        const SizedBox(height: 8),
        const ChatMessage(me: false, text: 'Deux tests échouent sur la fermeture auto : le délai attendu est 45 s, le code dit 60 s.'),
        const SizedBox(height: 8),
        TaskCard(title: 'Corrige la fermeture auto', subtitle: 'Modifie island_machine.dart', live: true, onTap: () => setState(() => _view = 0)),
      ],
    );
    return SideFrame(
      child: Stack(
        children: [
          SideHead(
            title: 'Corrige les tests du moteur',
            small: true,
            leading: RoundButton('left', size: 34, onPressed: () {}, tooltip: 'Retour'),
            actions: [RoundButton('stop', size: 34, onPressed: () {}, tooltip: 'Arrêter l’agent')],
          ),
          Positioned.fill(
            top: 68,
            bottom: 90,
            child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 2, 16, 16), child: _view == 0 ? suivi : chat),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: Composer(
              placeholder: 'Écris à cet agent…',
              options: Segmented(
                options: const ['Suivi', 'Chat'],
                selected: _view,
                size: SegmentSize.field,
                onChanged: (i) => setState(() => _view = i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The kit column of `composants.html`, then what `ux-a.html` added.
class KitParts extends StatefulWidget {
  const KitParts({super.key});

  @override
  State<KitParts> createState() => _KitPartsState();
}

class _KitPartsState extends State<KitParts> {
  bool _sending = false;

  void _send() {
    setState(() => _sending = true);
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _sending = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    Widget section(String title, List<Widget> lines, {String? caption}) => Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: uiText(12.5, weight: FontWeight.w600, color: ui.text2),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: lines[i],
            ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(caption, style: uiText(12.5, color: ui.text2)),
              ),
            ),
        ],
      ),
    );
    Widget line(List<Widget> children) => Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: children);
    final sep = Container(width: 1, height: 26, color: ui.line, margin: const EdgeInsets.symmetric(horizontal: 4));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section(
          'Boutons',
          caption: 'Principal : noir (blanc en sombre), un seul par écran. Secondaire : gris en relief. Rond : une action en icône. Barre : un groupe d’actions posé sur une capsule. Réponses : petits boutons à plat, le carré blanc glisse vers la réponse appuyée.',
          [
            line([
              MButton('Lancer', kind: ButtonKind.primary, onPressed: () {}),
              MButton('Annuler', onPressed: () {}),
              MButton('Plus tard', kind: ButtonKind.ghost, onPressed: () {}),
            ]),
            line([
              MButton('Oui', small: true, kind: ButtonKind.primary, onPressed: () {}),
              MButton('Non', small: true, onPressed: () {}),
              sep,
              const MButton('Lancer', kind: ButtonKind.primary),
              MButton(_sending ? 'Envoi…' : 'Envoyer', kind: ButtonKind.primary, loading: _sending, onPressed: _send),
            ]),
            // Oui / Non of a waiting agent (validated 2026-09-30).
            line([
              AnswerBar(answers: [('Non', () {}), ('Oui', () {})]),
              sep,
              AnswerBar(answers: [('Toujours', () {}), ('Non', () {}), ('Oui', () {})]),
            ]),
            line([
              for (final i in ['folder', 'sliders', 'plus']) RoundButton(i, onPressed: () {}),
              RoundButton('up', ink: true, onPressed: () {}),
              RoundButton('more', size: 34, onPressed: () {}),
              RoundButton('x', size: 26, onPressed: () {}),
            ]),
            ActionBar(
              children: [
                RoundButton('clip', onPressed: () {}),
                MButton('Envoyer à Téléphone', icon: 'share', kind: ButtonKind.primary, onPressed: () {}),
                RoundButton('sliders', onPressed: () {}),
              ],
            ),
          ],
        ),
        section('Sélecteurs', [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Agent', style: uiText(12.5, color: ui.text2)),
              const SizedBox(height: 8),
              Local(0, (v, set) => Segmented(options: const ['Claude', 'Codex'], selected: v, onChanged: set)),
            ],
          ),
          Local(0, (v, set) => Segmented(options: const ['Tous', 'En cours', 'Finis'], selected: v, onChanged: set)),
          line([
            Local(true, (v, set) => MSwitch(value: v, onChanged: set)),
            Local(false, (v, set) => MSwitch(value: v, onChanged: set)),
            sep,
            Local(true, (v, set) => MChip('Important', count: 2, on: v, onTap: () => set(!v))),
            Local(false, (v, set) => MChip('À répondre', count: 1, on: v, onTap: () => set(!v))),
            MChip('mikky', soft: true, icon: 'folder', trailingIcon: 'down', onTap: () {}),
          ]),
          Local(0, (v, set) => Segmented(options: const ['Claude', 'Codex'], selected: v, size: SegmentSize.xs, onChanged: set)),
        ]),
        section('Champs', [
          const SearchField(icon: 'search', placeholder: 'Chercher une session, un fichier…'),
          SearchField(
            placeholder: 'Nom du projet',
            controller: TextEditingController(text: 'mikky'),
          ),
          Container(
            width: 296,
            padding: const EdgeInsets.all(12),
            color: ui.island,
            child: Composer(
              placeholder: 'Que doit faire l’agent ?',
              options: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ComposerChip('mikky', icon: 'folder', onTap: () {}),
                  const SizedBox(width: 6),
                  ComposerChip('Claude', onTap: () {}),
                ],
              ),
            ),
          ),
        ]),
        section(
          'Navigation',
          caption: 'Barre de titre avec retour pour les écrans de détail. Barre d’onglets flottante (gardée pour plus tard), et sa version en icônes seules.',
          [
            Surface(
              width: 300,
              color: ui.raise,
              shadows: [CssShadow(0, 0, 0, ui.hlEdge, spread: 1, inset: true), ...ui.shBar],
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  RoundButton('left', size: 34, onPressed: () {}),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Réglages',
                        style: uiText(15, weight: FontWeight.w600, color: ui.text),
                      ),
                    ),
                  ),
                  RoundButton('more', size: 34, onPressed: () {}),
                ],
              ),
            ),
            SizedBox(
              width: 296,
              child: Local(
                0,
                (v, set) => MTabBar(
                  selected: v,
                  onChanged: set,
                  items: const [
                    TabItem('agents', label: 'Agents', dot: true),
                    TabItem('share', label: 'Partage'),
                    TabItem('mail', label: 'Mails', count: 2),
                  ],
                ),
              ),
            ),
            Local(
              0,
              (v, set) => MTabBar(
                mini: true,
                selected: v,
                onChanged: set,
                items: const [TabItem('agents'), TabItem('share'), TabItem('mail'), TabItem('sliders')],
              ),
            ),
          ],
        ),
        section('États d’un agent', [
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final (s, b, small) in [
                (UiStatus.working, 'Travaille', 'carré bleu qui vit'),
                (UiStatus.thinking, 'Réfléchit', 'carré violet qui vit'),
                (UiStatus.approval, 'Attend ton feu vert', 'carré orange qui vit'),
                (UiStatus.finished, 'Terminé', 'carré vert clair, figé'),
                (UiStatus.error, 'Erreur', 'carré rouge qui vit'),
                (UiStatus.limited, 'Limité', 'carré jaune qui vit'),
                (UiStatus.sleeping, 'Dort', 'carré gris qui vit'),
              ])
                SizedBox(
                  width: 200,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 8, 4),
                    child: Row(
                      children: [
                        StatusDot(s),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b,
                              style: uiText(13.5, weight: FontWeight.w600, color: ui.text),
                            ),
                            Text(small, style: uiText(12, color: ui.text2)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ]),
        section('Retours', [
          SizedBox(
            width: 300,
            child: Toast(
              icon: 'file',
              title: 'IMG_2041.jpg reçue',
              subtitle: 'De Téléphone · rangée dans Téléchargements',
              action: MButton('Ouvrir', small: true, onPressed: () {}),
            ),
          ),
          const SizedBox(width: 380, child: ProgressBar(value: .4)),
          const SizedBox(width: 380, child: ProgressBar()),
          line([
            const Spinner(),
            Text('Recherche des appareils…', style: uiText(13, color: ui.text2)),
            sep,
            Stack(
              clipBehavior: Clip.none,
              children: [
                RoundButton('mail', onPressed: () {}),
                Positioned(top: -4, right: -6, child: CountBadge(2, ring: ui.board)),
              ],
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                RoundButton('agents', onPressed: () {}),
                Positioned(top: 0, right: 0, child: DotBadge(ring: ui.board)),
              ],
            ),
            const TypingDots(),
          ]),
          // Set aside for now (user requests, 2026-09-30): the launcher, and
          // the star tried on Mikky thinking.
          // The pixel squares, bigger (after SmoothUI's agent avatar).
          line([
            for (final st in UiStatus.values) PixelStatus(st, size: 28),
            Text('Carrés d’état', style: uiText(13, color: ui.text2)),
          ]),
          // Pixel-art effects to try (2026-09-30): sparkle, firework, galaxy,
          // in four palettes.
          for (final kind in PixelFxKind.values)
            line([
              SizedBox(
                width: 76,
                child: Text(switch (kind) {
                  PixelFxKind.sparkle => 'Étincelle',
                  PixelFxKind.firework => 'Feu d’artifice',
                  PixelFxKind.fireworkSoft => 'Plus simple',
                  PixelFxKind.galaxy => 'Galaxie',
                }, style: uiText(13, color: ui.text2)),
              ),
              for (final p in PixelFxPalette.all) PixelFx(kind: kind, palette: p),
            ]),
          line([
            const DotSnake(UiStatus.working),
            Text('Lanceur', style: uiText(13, color: ui.text2)),
            sep,
            const ThinkingStar(size: 30),
            Text('Étoile qui réfléchit', style: uiText(13, color: ui.text2)),
          ]),
        ]),
        section('Logos des outils', [
          Wrap(spacing: 14, runSpacing: 10, children: [
            for (final b in Brand.values)
              Row(mainAxisSize: MainAxisSize.min, children: [
                BrandLogo(b, size: 20),
                const SizedBox(width: 6),
                Text(b.label, style: uiText(13, weight: FontWeight.w600, color: ui.text)),
              ]),
          ]),
        ]),
        section('Fil d’un agent', [
          const TaskCard(
            title: 'Tâche terminée',
            subtitle: '3 étapes · 1 fichier · 2 min',
            initiallyOpen: true,
            steps: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MetroStep(kind: StepKind.done, past: true, first: true, child: Text('Lire la spec')),
                MetroStep(kind: StepKind.done, past: true, child: Text('Écrire le résumé')),
                MetroStep(kind: StepKind.end, past: true, last: true, child: Text('Terminé · 1 fichier')),
              ],
            ),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final n in iconNames) MikkyIcon(n, size: 20, color: ui.text)]),
        ]),
      ],
    );
  }
}

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
