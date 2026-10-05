import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/enchant.dart';
import '../side/session_cards.dart';
import '../side/session_text.dart';
import '../side/session_views.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/feedback.dart';
import '../ui/field.dart';
import '../ui/icons.dart';
import '../ui/messages.dart';
import '../ui/pixel_fx.dart';
import '../ui/side.dart';
import '../ui/status.dart';
import '../ui/tasks.dart';
import '../ui/tokens.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

// ----------------------------------------------------------------- agent

/// An agent's page in its window, fed by a made-up session (the same
/// thread as the app's).
class AgentMock extends StatefulWidget {
  const AgentMock({
    super.key,
    required this.title,
    required this.log,
    this.external = false,
    this.adapterPid,
    this.scrolled = false,
    this.paused = false,
    this.enchanted = false,
    this.finished = false,
    this.framed = true,
  });

  /// In its own window (else in the caller's: the top's island).
  final bool framed;

  /// Stopped by its limit, and already under the spell (« Ensorceler »).
  final bool enchanted;

  /// Its limit « Terminée »: only « Relance auto » is left.
  final bool finished;

  /// Its name (the page does not show it any more; kept to tell the
  /// frames apart in the code).
  final String title;
  final SessionLog log;

  /// Scrolled down a little: the thread passes under the buttons.
  final bool scrolled;

  /// Started in VS Code or a terminal: followed, read only.
  final bool external;

  /// PID of a Mikky-controlled ACP adapter, on its own host.
  final int? adapterPid;

  /// Put on hold by the user: « En pause » and Reprendre under the thread.
  final bool paused;

  @override
  State<AgentMock> createState() => _AgentMockState();
}

class _AgentMockState extends State<AgentMock> {
  late final _scroll = ScrollController(initialScrollOffset: widget.scrolled ? 120 : 0);

  // Its own agent id for the spell, as the app's page would have.
  late final _id = 'board-${identityHashCode(this)}';
  late final _limit = LimitHooks(_id, (_) async {}, finish: () {}, finished: widget.finished);

  @override
  void initState() {
    super.initState();
    // As the app: the page opens at the end of the thread.
    if (!widget.scrolled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    if (widget.enchanted) {
      // Seen from when the limit hit, so the spell waits until its time.
      Enchantments.instance.enchant(_id, widget.log.limitResetsAt, _limit.send, now: widget.log.lastEventAt);
    }
  }

  @override
  void dispose() {
    Enchantments.instance.cancel(_id);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final log = widget.log;
    final working = log.working;
    final usage = usageLine(log);
    final content = <Widget>[
      if (widget.adapterPid != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('Adaptateur ACP · PID ${widget.adapterPid} · Windows', style: uiText(11.5, color: ui.text3, tabular: true)),
        ),
      if (usage.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10), child: Text(usage, style: uiText(TextSize.caption, color: ui.text3, tabular: true))),
      ...threadOf(context, log, limit: _limit),
      if (widget.paused)
        Padding(padding: const EdgeInsets.only(top: 12), child: PausedCard(onResume: () {}))
      else if (log.question != null)
        Padding(padding: const EdgeInsets.only(top: 12), child: QuestionCard(question: log.question!, onAnswer: (_) {}))
      else if (log.pending.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 12), child: AskCard(log: log, onAnswer: (_) {})),
    ];
    final readOnly = widget.external && working;
    final page = Stack(children: [
        // As the app: no title, the thread up to the top, the buttons over it.
        Positioned.fill(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(16, 62, 16, readOnly ? 56 : 78),
            child: ReadingColumn(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content)),
          ),
        ),
        // Softer on top (user request, 2026-09-30: « trop puissant »).
        const Positioned(top: 0, left: 0, right: 0, child: TopBlur()),
        // Only behind the field, not above it (user request, 2026-09-30).
        Positioned(left: 0, right: 0, bottom: 0, child: EdgeBlur(top: false, height: readOnly ? 44 : 54)),
        Positioned(top: 20, left: 0, right: 0, child: Center(child: SpellStar(id: _id, limited: log.statusAt(log.lastEventAt ?? DateTime(2026)) == AgentStatus.rateLimited))),
        SideHead(
          leading: RoundButton('left', size: 34, onPressed: () {}, tooltip: 'Retour'),
          actions: [
            RoundButton.menu(size: 34, onPressed: () {}, tooltip: 'Menu'),
          ],
        ),
        if (!readOnly)
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: ReadingColumn(
              child: Composer(
                glass: true,
                placeholder: working ? 'Écris à cet agent…' : 'Continuer avec cet agent…',
              ),
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
              Expanded(child: Text('Session extérieure : activité observée, processus non vérifié.', style: uiText(TextSize.caption, color: ui.text3, height: 1.35))),
            ]),
          ),
      ]);
    return widget.framed ? SideFrame(child: page) : page;
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
          bottom: 92,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const MiniMikky(size: 64),
            const SizedBox(height: 8),
            Text('Qu’est-ce qu’on lance ?', style: uiText(TextSize.body, weight: FontWeight.w500, color: ui.text2)),
            if (starting) ...[
              const SizedBox(height: 14),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Spinner(size: 14),
                const SizedBox(width: 8),
                Text('Démarrage…', style: uiText(TextSize.small, color: ui.text2)),
              ]),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: Text(error!, textAlign: TextAlign.center, style: uiText(TextSize.small, color: ui.red)),
              ),
          ]),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 12,
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

final agentBoard = BoardSpec('Agent', 'La page d’un agent : le fil, attentes, fins', (context) => [
  BoardSection(
    title: 'Au travail',
    note: 'Un seul fil (2026-10-05) : tes messages, et pour chaque tâche tout ce qui s’y passe dans l’ordre — ce que l’agent dit en route, ses actions en grandes lignes (un clic montre les outils), le code en direct sous l’action en cours, le plan en haut s’il en a un ; sa réponse sous la tâche. Pas de titre ni de bandeau : le fil va jusqu’en haut, les boutons flottent dessus (retour ; « ··· », le menu : mettre en pause ou reprendre, arrêter l’agent, VS Code, dossier, renommer, épingler, archiver, supprimer).',
    frames: [
      BoardFrame(label: 'Avec un plan', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.working(), adapterPid: 12345)),
      BoardFrame(
        label: 'Sans plan',
        note: 'Les outils regroupés en grandes lignes, colorées par action, entre ce que l’agent dit.',
        child: AgentMock(title: 'Ajoute un test Codex', log: FakeSessions.workingNoPlan()),
      ),
      BoardFrame(
        label: 'Session hors de Mikky',
        note: 'Lancée dans VS Code ou un terminal : le même fil, ses messages et ses actions en direct ; Mikky lit son activité, sans confirmer que son processus tourne et sans pouvoir lui répondre.',
        child: AgentMock(title: 'Refactor du lecteur', log: FakeSessions.working(), external: true),
      ),
    ],
  ),
  BoardSection(
    title: 'Attend',
    frames: [
      BoardFrame(label: 'Feu vert pour une commande', child: AgentMock(title: 'Met à jour le site', log: FakeSessions.approval())),
      BoardFrame(label: 'Question à choix', child: AgentMock(title: 'Stockage des tâches', log: FakeSessions.question())),
    ],
  ),
  BoardSection(
    title: 'Fini',
    frames: [
      BoardFrame(label: 'Terminé, la conversation continue', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.done())),
      BoardFrame(
        label: 'Défilé',
        note: 'Le fil passe sous les boutons et sous le champ, flouté.',
        child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.done(), scrolled: true),
      ),
      BoardFrame(
        label: 'Limite atteinte',
        note: 'L’abonnement est au bout : étoile jaune en haut ; une ligne, sans encadré, « Limite atteinte · reprend à 17 h 10 » (l’heure lue dans le message de l’agent), puis la barre à plat : « Terminer » (on n’attend plus) ou « Relance auto ».',
        child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.limited()),
      ),
      BoardFrame(
        label: 'Limite atteinte, terminée',
        note: 'Après « Terminer » : il ne reste que « Relance auto » (qui la remet en attente de la reprise, ensorcelée).',
        child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.limited(), finished: true),
      ),
      BoardFrame(
        label: 'Ensorcelée',
        note: 'La même ligne : « Ensorcelé · se relance à 17 h 11 », l’étoile violette, et « Terminer » pour refuser la relance ; l’étoile violette en haut au milieu.',
        child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.limited(), enchanted: true),
      ),
      BoardFrame(label: 'Erreur', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.error())),
      BoardFrame(label: 'Arrêté', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.cancelled())),
      BoardFrame(
        label: 'En pause',
        note: '« Mettre en pause » dans le menu ··· ; Reprendre lui dit de continuer. « Arrêter l’agent » (fin du processus) est dans le même menu.',
        child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.cancelled(), paused: true),
      ),
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
          label: 'Réponse à lire',
          note: 'Comme une note dans Obsidian : 14,5 px, interligne 1,65 ; titres, listes, tableau, citation, trait.',
          child: _Pane([
            ChatMessage(
              me: false,
              text: '# Le notch\n\n'
                  'Mikky regarde la **dernière tâche** au travail ; les autres applications sont à droite.\n\n'
                  '## Ce qui change\n\n'
                  '- Les tuiles sont larges\n'
                  '- Le logiciel remplace le *modèle*\n'
                  '  - VS Code, c’est VS Code\n\n'
                  '| Partie | Largeur |\n'
                  '| --- | --- |\n'
                  '| Mikky et sa tâche | 342 |\n'
                  '| Applications | 418 |\n\n'
                  '> Pas de bloc pour rien.\n\n'
                  '---\n\n'
                  '### Plus tard\n\n'
                  'Ctrl + clic ouvre l’agent dans son logiciel.',
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
      note: 'Une tâche fait partie de la page : son état en pixels, son titre, ses chiffres. Ouverte : tout ce qui s’y passe dans l’ordre (2026-10-05) — ce que l’agent dit en route, ses actions en points d’étape, un message glissé ; un clic sur une étape montre ses outils. Au-delà de 40 lignes, le début se replie sous « N plus tôt ».',
      frames: [
        const BoardFrame(
          label: 'Repliée',
          child: _Pane([TaskSection(status: UiStatus.finished, title: 'Tâche terminée', meta: '3 étapes · 1 fichier · 2 min', children: [TaskStep(label: 'Lit la spec')])]),
        ),
        BoardFrame(
          label: 'Le déroulement',
          note: 'Ce que l’agent dit en entier ; ses réflexions en gris clair, sur deux lignes. Couleur par action : crée vert, modifie bleu, commande orange, internet violet, supprime rouge ; lire et chercher en gris.',
          child: _Pane([
            TaskSection(
              status: UiStatus.working,
              title: 'Au travail',
              meta: '5 étapes · 2 fichiers',
              initiallyOpen: true,
              children: [
                const NoteLine('Je regarde d’abord comment le lecteur compte les jetons.', thought: true),
                const SizedBox(height: 8),
                const TaskStep(label: 'Lit 3 fichiers'),
                const SizedBox(height: 8),
                const NoteLine('Le lecteur ignore `token_count` quand la fenêtre manque. J’ajoute un test pour ce cas.'),
                const SizedBox(height: 8),
                TaskStep(label: 'Crée usage_test.dart', tone: PixelFxPalette.green(ui)),
                TaskStep(label: 'Modifie codex_reader.dart', tone: PixelFxPalette.blue),
                TaskStep(label: 'Va sur internet', tone: PixelFxPalette.violet),
                const TaskStep(label: 'Lance une commande', state: TaskStepState.failed, note: 'échec'),
                const SizedBox(height: 8),
                const ChatMessage(me: true, text: 'Regarde aussi le délai', meta: '14:02'),
                const SizedBox(height: 8),
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
              children: [
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
        const BoardFrame(
          label: 'Arrêtée, en erreur',
          child: _Pane([
            TaskSection(status: UiStatus.paused, title: 'Tâche arrêtée', meta: '2 étapes', children: [TaskStep(label: 'Lit 2 fichiers')]),
            TaskSection(status: UiStatus.error, title: 'Tâche en erreur', meta: '1 étape', children: [TaskStep(label: 'Lance une commande', state: TaskStepState.failed, note: 'échec')]),
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
