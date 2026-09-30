import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../side/session_views.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/cards.dart';
import '../ui/feedback.dart';
import '../ui/field.dart';
import '../ui/icons.dart';
import '../ui/pixel_fx.dart';
import '../ui/selectors.dart';
import '../ui/side.dart';
import '../ui/thread.dart';
import '../ui/tokens.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

// ------------------------------------------------------------------ home

/// A row of the home, as sample data.
typedef SampleRow = (String title, Brand brand, String subtitle, String who);

/// The home in its window, with sample agents in each group (the same
/// widgets as the app's home).
class HomeMock extends StatefulWidget {
  const HomeMock({
    super.key,
    this.waiting = const [],
    this.working = const [],
    this.done = const [],
    this.history = 0,
    this.limits,
    this.historyOpen = false,
  });

  final List<SampleRow> waiting;
  final List<(SampleRow, UiStatus)> working;
  final List<SampleRow> done;
  final int history;
  final String? limits;
  final bool historyOpen;

  @override
  State<HomeMock> createState() => _HomeMockState();
}

class _HomeMockState extends State<HomeMock> {
  late final _open = {'wait': true, 'work': true, 'done': true, 'old': widget.historyOpen};

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final body = <Widget>[];
    void group(String id, String label, Color color, UiStatus? status, int n, List<Widget> rows) {
      if (n == 0) return;
      body.add(GroupHeader(
        label: label,
        color: color,
        status: status,
        count: n,
        open: _open[id]!,
        first: body.isEmpty,
        onTap: () => setState(() => _open[id] = !_open[id]!),
      ));
      if (_open[id]!) body.addAll(rows);
    }

    group('wait', 'En attente', ui.amber, UiStatus.approval, widget.waiting.length, [
      for (final (t, b, s, w) in widget.waiting)
        AgentCard(
          status: UiStatus.approval,
          title: t,
          who: w,
          brand: b,
          subtitle: s,
          style: AgentCardStyle.waiting,
          onTap: () {},
          actions: WaitActions(command: 'npm run build', onYes: () {}, onNo: () {}),
        ),
    ]);
    group('work', 'Travaillent', ui.blue, UiStatus.working, widget.working.length, [
      for (final ((t, b, s, w), st) in widget.working) AgentCard(status: st, title: t, who: w, brand: b, subtitle: s, onTap: () {}),
    ]);
    group('done', 'Terminés', ui.green, UiStatus.finished, widget.done.length, [
      for (final (t, b, s, w) in widget.done)
        AgentCard(status: UiStatus.finished, title: t, who: w, brand: b, subtitle: s, style: AgentCardStyle.done, onTap: () {}),
    ]);
    group('old', 'Historique', ui.grey, null, widget.history, [
      for (final (t, w) in [('Ajoute la position à droite', 'Claude'), ('Traduis le README', 'Codex'), ('Corrige le hook souris', 'Claude')])
        AgentCard(status: UiStatus.finished, title: t, who: w, style: AgentCardStyle.old, onTap: () {}),
    ]);
    if (widget.limits != null) {
      body.add(Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 6, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: BrandLogo(Brand.codex, size: 12)),
          const SizedBox(width: 6),
          Expanded(child: Text(widget.limits!, style: uiText(11.5, color: ui.text3, height: 1.3, tabular: true))),
        ]),
      ));
    }
    return SideFrame(
      child: Stack(children: [
        SideHead(title: 'Agents', leading: const HeadMikky(), actions: [RoundButton('more', size: 34, onPressed: () {})]),
        Positioned.fill(
          top: 68,
          child: body.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(32, 120, 32, 0),
                  child: Column(children: [
                    Text('Aucun agent pour l’instant', textAlign: TextAlign.center, style: uiText(14, weight: FontWeight.w500, color: ui.text2)),
                    const SizedBox(height: 6),
                    Text('La flèche en bas lance Claude ou Codex.', textAlign: TextAlign.center, style: uiText(12.5, color: ui.text3)),
                  ]),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 72),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
                ),
        ),
        Positioned(right: 16, bottom: 16, child: RoundButton('go', size: 46, ink: true, onPressed: () {}, tooltip: 'Nouvel agent')),
      ]),
    );
  }
}

const _waiting = ('Met à jour le site', Brand.codex, 'Veut lancer une commande', 'WSL');
const _working = [
  (('Corrige les tests du moteur', Brand.claude, 'Modifie island_machine.dart', ''), UiStatus.working),
  (('Prépare le plan de l’API', Brand.codex, 'Réfléchit au plan', ''), UiStatus.thinking),
];
const _done = [
  ('Résume la spec', Brand.claude, 'Il y a 2 min', ''),
  ('Ajoute les tests du lecteur Codex', Brand.codex, 'Il y a 14 min', 'WSL'),
  ('Corrige le clic en dehors', Brand.claude, 'Il y a 1 h', ''),
];

final homeBoard = BoardSpec('Accueil', 'La liste des agents, dans chaque situation', (context) => [
  const BoardSection(
    title: 'Accueil',
    note: 'Les agents en groupes repliables. Clic sur un titre : replie ; survol d’une ligne : fond gris ; la flèche noire lance un nouvel agent.',
    frames: [
      BoardFrame(label: 'Vide', note: 'Premier lancement, aucun agent.', child: HomeMock()),
      BoardFrame(label: 'Un agent attend', note: 'Oui / Non directement sur l’accueil.', child: HomeMock(waiting: [_waiting])),
      BoardFrame(label: 'Au travail', child: HomeMock(working: _working)),
      BoardFrame(label: 'Tout à la fois', note: 'Attend, travaillent, terminés, historique replié.', child: HomeMock(waiting: [_waiting], working: _working, done: _done, history: 12)),
      BoardFrame(
        label: 'Historique ouvert, limites Codex',
        child: HomeMock(done: _done, history: 12, historyOpen: true, limits: 'Codex · 5 h : 38 % · semaine : 12 % · repart à 17 h 10'),
      ),
    ],
  ),
]);

// ----------------------------------------------------------------- agent

/// An agent's page in its window, fed by a made-up session (the same
/// Suivi and Chat as the app's).
class AgentMock extends StatefulWidget {
  const AgentMock({super.key, required this.title, required this.log, this.chat = false, this.external = false, this.scrolled = false});

  /// Its name (the page does not show it any more; kept to tell the
  /// frames apart in the code).
  final String title;
  final SessionLog log;

  /// Scrolled down a little: the thread passes under the buttons.
  final bool scrolled;

  /// Starts on Chat (else Suivi, while it works).
  final bool chat;

  /// Started in VS Code or a terminal: followed, read only.
  final bool external;

  @override
  State<AgentMock> createState() => _AgentMockState();
}

class _AgentMockState extends State<AgentMock> {
  late int _view = widget.chat ? 1 : 0;
  late final _scroll = ScrollController(initialScrollOffset: widget.scrolled ? 150 : 0);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final log = widget.log;
    final working = log.working;
    final suivi = working && _view == 0;
    final usage = usageLine(log);
    final content = <Widget>[
      if (usage.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10), child: Text(usage, style: uiText(11.5, color: ui.text3, tabular: true))),
      ...(suivi ? suiviOf(context, log) : chatOf(context, log, toSuivi: () => setState(() => _view = 0))),
      if (log.question != null)
        Padding(padding: const EdgeInsets.only(top: 12), child: QuestionCard(question: log.question!, onAnswer: (_) {}))
      else if (log.pending.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 12), child: AskCard(log: log, onAnswer: (_) {})),
    ];
    final readOnly = widget.external && working;
    return SideFrame(
      child: Stack(children: [
        // As the app: no title, the thread up to the top, the buttons over it.
        Positioned.fill(
          bottom: readOnly ? 44 : (working ? 90 : 78),
          child: TopFade(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 62, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content),
            ),
          ),
        ),
        SideHead(
          leading: RoundButton('left', size: 34, onPressed: () {}, tooltip: 'Retour'),
          actions: [
            if (working && !widget.external) RoundButton('stop', size: 34, onPressed: () {}, tooltip: 'Arrêter l’agent'),
            RoundButton('more', size: 34, onPressed: () {}, tooltip: 'Plus'),
          ],
        ),
        if (!readOnly)
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: Composer(
              placeholder: working ? 'Écris à cet agent…' : 'Continuer avec cet agent…',
              options: working
                  ? Segmented(options: const ['Suivi', 'Chat'], selected: _view, size: SegmentSize.field, onChanged: (i) => setState(() => _view = i))
                  : null,
            ),
          )
        else
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Row(children: [
              MikkyIcon('lock', size: 13, color: ui.text3),
              const SizedBox(width: 6),
              Expanded(child: Text('Ouverte dans VS Code ou un terminal : Mikky la suit sans y toucher.', style: uiText(11.5, color: ui.text3, height: 1.35))),
            ]),
          ),
      ]),
    );
  }
}

/// « Nouvel agent »: Mikky, the question, the field with its folder and
/// model.
class NewAgentMock extends StatelessWidget {
  const NewAgentMock({super.key, this.starting = false, this.error});

  final bool starting;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SideFrame(
      child: Stack(children: [
        SideHead(title: 'Nouvel agent', small: true, leading: RoundButton('left', size: 34, onPressed: () {}, tooltip: 'Retour')),
        Positioned.fill(
          top: 68,
          bottom: 90,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const MiniMikky(size: 64),
            const SizedBox(height: 8),
            Text('Qu’est-ce qu’on lance ?', style: uiText(14, weight: FontWeight.w500, color: ui.text2)),
            if (starting) ...[
              const SizedBox(height: 14),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Spinner(size: 14),
                const SizedBox(width: 8),
                Text('Démarrage…', style: uiText(12.5, color: ui.text2)),
              ]),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: Text(error!, textAlign: TextAlign.center, style: uiText(12, color: ui.red)),
              ),
          ]),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 14,
          child: Composer(
            placeholder: 'Que doit faire l’agent ?',
            options: Row(mainAxisSize: MainAxisSize.min, children: [
              ComposerChip('mikky', icon: 'folder', onTap: () {}),
              const SizedBox(width: 6),
              ComposerChip('Claude · Opus', leading: const BrandLogo(Brand.claude, size: 12), onTap: () {}),
            ]),
          ),
        ),
      ]),
    );
  }
}

final agentBoard = BoardSpec('Agent', 'La page d’un agent : Suivi, Chat, attentes, fins', (context) => [
  BoardSection(
    title: 'Au travail',
    note: 'Suivi (la ligne de métro) ou Chat, au choix sous le champ. Pas de titre ni de bandeau : le fil va jusqu’en haut, les boutons flottent dessus (retour ; arrêter, pendant qu’il travaille ; « ··· », le menu : VS Code, dossier, renommer, épingler, archiver, supprimer).',
    frames: [
      BoardFrame(label: 'Suivi', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.working())),
      BoardFrame(label: 'Chat, avec un plan', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.working(), chat: true)),
      BoardFrame(
        label: 'Chat, sans plan',
        note: 'Les outils regroupés en grandes lignes, colorées par action.',
        child: AgentMock(title: 'Ajoute un test Codex', log: FakeSessions.workingNoPlan(), chat: true),
      ),
      BoardFrame(
        label: 'Session hors de Mikky',
        note: 'Lancée dans VS Code : suivie, sans champ.',
        child: AgentMock(title: 'Refactor du lecteur', log: FakeSessions.working(), external: true),
      ),
    ],
  ),
  BoardSection(
    title: 'Attend',
    frames: [
      BoardFrame(label: 'Feu vert pour une commande', child: AgentMock(title: 'Met à jour le site', log: FakeSessions.approval(), chat: true)),
      BoardFrame(label: 'Question à choix', child: AgentMock(title: 'Stockage des tâches', log: FakeSessions.question(), chat: true)),
    ],
  ),
  BoardSection(
    title: 'Fini',
    frames: [
      BoardFrame(label: 'Terminé, la conversation continue', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.done())),
      BoardFrame(
        label: 'Défilé',
        note: 'Le fil monte jusqu’en haut, sous les boutons.',
        child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.done(), scrolled: true),
      ),
      BoardFrame(label: 'Erreur (limite)', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.error())),
      BoardFrame(label: 'Arrêté', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.cancelled())),
    ],
  ),
  const BoardSection(
    title: 'Nouvel agent',
    frames: [
      BoardFrame(label: 'Au départ', child: NewAgentMock()),
      BoardFrame(label: 'Démarrage', child: NewAgentMock(starting: true)),
      BoardFrame(label: 'Erreur', child: NewAgentMock(error: 'Codex n’est pas installé dans WSL.')),
    ],
  ),
]);

// -------------------------------------------------------------- messages

/// A piece of the thread on the window's background, 320 wide.
class _Pane extends StatelessWidget {
  const _Pane(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(color: ui.island, borderRadius: BorderRadius.circular(22), border: Border.all(color: ui.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < children.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 10), child: children[i]),
      ]),
    );
  }
}

final messagesBoard = BoardSpec('Messages', 'Le fil : bulles, réponses, tâches, étapes', (context) {
  final ui = MikkyUi.of(context);
  return [
    const BoardSection(
      title: 'Bulles et réponses',
      note: 'Tes messages en bulles noires à droite ; les réponses de l’agent sans bulle, sur toute la largeur.',
      frames: [
        BoardFrame(
          label: 'Ton message',
          child: _Pane([
            ChatMessage(me: true, text: 'Tu peux regarder pourquoi les tests du moteur cassent ?', meta: '14:00'),
            ChatMessage(me: true, text: 'Ajoute aussi un test pour le cas limite.'),
          ]),
        ),
        BoardFrame(
          label: 'Réponse simple',
          child: _Pane([ChatMessage(me: false, text: 'Deux tests échouent sur la fermeture auto : le délai attendu est **45 s**, le code dit 60 s.')]),
        ),
        BoardFrame(
          label: 'Réponse avec listes',
          child: _Pane([
            ChatMessage(
              me: false,
              text: 'Voilà ce que j’ai fait :\n\n'
                  '1. Lu la spec de l’étape 1 et relevé les décisions qui touchent la petite fenêtre\n'
                  '2. Écrit le résumé\n'
                  '   en français, court\n\n'
                  '- Trois points retenus\n'
                  '- Un point à valider avec toi\n'
                  '  - la position de l’île',
            ),
          ]),
        ),
        BoardFrame(
          label: 'Réponse avec code et lien',
          child: _Pane([
            ChatMessage(
              me: false,
              text: 'Dans `packages/mikky_engine` :\n\n```powershell\nC:\\dev\\flutter\\bin\\dart.bat test\n```\n\nPlus de détails : https://dart.dev/tools/dart-test',
            ),
          ]),
        ),
      ],
    ),
    BoardSection(
      title: 'Tâches',
      note: 'Une tâche fait partie de la page : son état en pixels, son titre, ses chiffres. Ouverte : les grandes lignes en points d’étape ; un clic sur une étape montre ses outils ; « Voir le détail » montre tout.',
      frames: [
        const BoardFrame(
          label: 'Repliée',
          child: _Pane([TaskSection(status: UiStatus.finished, title: 'Tâche terminée', meta: '3 étapes · 1 fichier · 2 min', steps: [TaskStep(label: 'Lit la spec')])]),
        ),
        BoardFrame(
          label: 'Grandes lignes',
          note: 'Couleur par action : crée vert, modifie bleu, commande orange, internet violet, supprime rouge ; lire et chercher en gris.',
          child: _Pane([
            TaskSection(
              status: UiStatus.working,
              title: 'Au travail',
              meta: '6 étapes · 2 fichiers',
              initiallyOpen: true,
              action: 'Suivi',
              onAction: () {},
              steps: [
                const TaskStep(label: 'Lit 3 fichiers'),
                TaskStep(label: 'Crée usage_test.dart', tone: PixelFxPalette.green(ui)),
                TaskStep(label: 'Modifie codex_reader.dart', tone: PixelFxPalette.blue),
                TaskStep(label: 'Va sur internet', tone: PixelFxPalette.violet),
                const TaskStep(label: 'Lance une commande', state: TaskStepState.failed, note: 'échec'),
                const TaskStep(label: 'Relance les tests', state: TaskStepState.now),
              ],
            ),
          ]),
        ),
        BoardFrame(
          label: 'Une étape ouverte',
          note: 'Ses outils : commande ou fichier en mono ; un clic sur un outil montre la sortie ou le code.',
          child: _Pane([
            TaskSection(
              status: UiStatus.finished,
              title: 'Tâche terminée',
              meta: '2 étapes · 2 min',
              initiallyOpen: true,
              steps: [
                TaskStep(
                  label: 'Lance une commande',
                  tone: PixelFxPalette.fire,
                  initiallyOpen: true,
                  detail: const ToolLine(
                    icon: 'agents',
                    title: 'Lancer les tests',
                    detail: 'dart test',
                    initiallyOpen: true,
                    body: OutputBox('00:02 +76: All tests passed!'),
                  ),
                ),
                TaskStep(label: 'Modifie island_machine.dart', tone: PixelFxPalette.blue),
              ],
            ),
          ]),
        ),
        BoardFrame(
          label: 'Tout le détail',
          note: 'Réflexions en gris clair, messages en cours de route, chaque outil.',
          child: _Pane([
            TaskSection(
              status: UiStatus.finished,
              title: 'Tâche terminée',
              meta: '2 étapes · 1 fichier',
              initiallyOpen: true,
              initiallyDetails: true,
              steps: [const TaskStep(label: 'Lit la spec'), TaskStep(label: 'Crée resume.md', tone: PixelFxPalette.green(ui))],
              details: [
                const NoteLine('Je lis la spec puis j’écris un résumé court.', thought: true),
                const ToolLine(icon: 'file', title: 'Lire la spec', detail: 'docs/spec.md'),
                ToolLine(
                  icon: 'file',
                  title: 'Écrire le résumé',
                  detail: 'docs/resume.md',
                  trailing: Text('+12', style: uiText(11.5, weight: FontWeight.w500, mono: true, color: ui.green)),
                ),
                const NoteLine('Résumé écrit, 12 lignes.'),
              ],
            ),
          ]),
        ),
        BoardFrame(
          label: 'Arrêtée, en erreur',
          child: _Pane([
            const TaskSection(status: UiStatus.sleeping, title: 'Tâche arrêtée', meta: '2 étapes', steps: [TaskStep(label: 'Lit 2 fichiers')]),
            const TaskSection(status: UiStatus.error, title: 'Tâche en erreur', meta: '1 étape', steps: [TaskStep(label: 'Lance une commande', state: TaskStepState.failed, note: 'échec')]),
          ]),
        ),
      ],
    ),
    const BoardSection(
      title: 'Attentes dans le fil',
      frames: [
        BoardFrame(label: 'Feu vert', child: SizedBox(width: 320, child: _AskSample())),
      ],
    ),
  ];
});

class _AskSample extends StatelessWidget {
  const _AskSample();

  @override
  Widget build(BuildContext context) => AskCard(log: FakeSessions.approval(), onAnswer: (_) {});
}
