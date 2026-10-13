import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/enchant.dart';
import '../side/agent_page.dart';
import '../side/session_cards.dart';
import '../ui/content/messages.dart';
import '../ui/content/side.dart';
import '../ui/content/tasks.dart';
import '../ui/content/thread_page.dart';
import '../ui/foundation/status.dart';
import '../ui/foundation/tokens.dart';
import '../ui/pixels/pixel_fx.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

// ----------------------------------------------------------------- agent

/// An agent's page on a board: the app's own page ([AgentPageView]), fed
/// by a made-up session, its actions doing nothing.
class AgentMock extends StatefulWidget {
  const AgentMock({
    super.key,
    required this.title,
    required this.log,
    this.external = false,
    this.canAnswerRequests,
    this.canQueueExternal = false,
    this.messages = const [],
    this.adapterPid,
    this.scrolled = false,
    this.paused = false,
    this.enchanted = false,
    this.finished = false,
    this.framed = true,
    this.mikky,
  });

  /// A trial: Mikky on the left of the page.
  final MikkyBeside? mikky;

  /// In its own window (else in the caller's: the notch).
  final bool framed;

  /// Stopped by its limit, and already under the spell (« Ensorceler »).
  final bool enchanted;

  /// Its limit « Terminée »: only « Relance auto » is left.
  final bool finished;

  /// Its name (the page does not show it; kept to tell the frames apart
  /// in the code).
  final String title;
  final SessionLog log;

  /// Scrolled down a little: the thread passes under the buttons.
  final bool scrolled;

  /// Started in VS Code or a terminal: observed, with an optional hook queue.
  final bool external;
  final bool? canAnswerRequests;
  final bool canQueueExternal;
  final List<ExternalMessage> messages;

  /// PID of a Mikky-controlled ACP adapter, on its own host.
  final int? adapterPid;

  /// Put on hold by the user: « En pause » and Reprendre under the thread.
  final bool paused;

  @override
  State<AgentMock> createState() => _AgentMockState();
}

class _AgentMockState extends State<AgentMock> {
  // Its own agent id for the spell, as the app's page would have.
  late final _id = 'board-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    if (widget.enchanted) {
      // Seen from when the limit hit, so the spell waits until its time.
      final log = widget.log;
      Enchantments.instance.enchant(_id, log.limitResetsAt, (_) async {}, now: log.lastEventAt);
    }
  }

  @override
  void dispose() {
    Enchantments.instance.cancel(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = OwnOverlay(child: Builder(builder: _page));
    return widget.framed ? SideFrame(child: page) : page;
  }

  Widget _page(BuildContext context) {
    final log = widget.log;
    return AgentPageView(
      model: AgentPageModel(
        id: _id,
        log: log,
        status: widget.paused ? AgentStatus.paused : log.statusAt(log.lastEventAt ?? DateTime(2026)),
        external: widget.external,
        canAnswerRequests: widget.canAnswerRequests,
        canQueueExternal: widget.canQueueExternal,
        messages: widget.messages,
        live: !widget.external,
        adapterPid: widget.adapterPid,
        limitFinished: widget.finished,
      ),
      actions: AgentPageActions(
        back: () {},
        send: (_) async {},
        answer: (_) {},
        answerQuestion: (_) {},
        resume: () {},
        finishLimit: () {},
        unfinishLimit: () {},
        menu: () {},
      ),
      scrolledTo: widget.scrolled ? 120 : null,
      mikky: widget.mikky,
    );
  }
}

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
      decoration: BoxDecoration(
        color: ui.island,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ui.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: children[i],
            ),
        ],
      ),
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
          child: _Pane([
            ChatMessage(
              me: false,
              text: 'Deux tests échouent sur la fermeture auto : le délai attendu est **45 s**, le code dit 60 s.',
            ),
          ]),
        ),
        BoardFrame(
          label: 'Réponse avec listes',
          child: _Pane([
            ChatMessage(
              me: false,
              text:
                  'Voilà ce que j’ai fait :\n\n'
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
              text:
                  '# Le notch\n\n'
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
          child: _Pane([
            TaskSection(
              status: UiStatus.finished,
              title: 'Tâche terminée',
              meta: '3 étapes · 1 fichier · 2 min',
              children: [TaskStep(label: 'Lit la spec')],
            ),
          ]),
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
                const NoteLine(
                  'Le lecteur ignore `token_count` quand la fenêtre manque. J’ajoute un test pour ce cas.',
                ),
                const SizedBox(height: 8),
                TaskStep(label: 'Crée usage_test.dart', tone: PixelFxPalette.green(ui)),
                const TaskStep(label: 'Modifie codex_reader.dart', tone: PixelFxPalette.blue),
                const TaskStep(label: 'Va sur internet', tone: PixelFxPalette.violet),
                const TaskStep(label: 'Lance une commande', state: TaskStepState.failed, note: 'échec'),
                const SizedBox(height: 8),
                const ChatMessage(me: true, text: 'Regarde aussi le délai', meta: '14:02'),
                const SizedBox(height: 8),
                const TaskStep(label: 'Relance les tests', state: TaskStepState.now),
              ],
            ),
          ]),
        ),
        const BoardFrame(
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
                  detail: ToolLine(
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
            TaskSection(
              status: UiStatus.paused,
              title: 'Tâche arrêtée',
              meta: '2 étapes',
              children: [TaskStep(label: 'Lit 2 fichiers')],
            ),
            TaskSection(
              status: UiStatus.error,
              title: 'Tâche en erreur',
              meta: '1 étape',
              children: [TaskStep(label: 'Lance une commande', state: TaskStepState.failed, note: 'échec')],
            ),
          ]),
        ),
      ],
    ),
    const BoardSection(
      title: 'Attentes dans le fil',
      frames: [
        BoardFrame(
          label: 'Feu vert',
          child: SizedBox(width: 320, child: _AskSample()),
        ),
      ],
    ),
  ];
});

class _AskSample extends StatelessWidget {
  const _AskSample();

  @override
  Widget build(BuildContext context) => AskCard(log: FakeSessions.approval(), onAnswer: (_) {});
}
