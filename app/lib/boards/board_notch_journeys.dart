import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../home/home_frame.dart';
import '../home/home_layout.dart';
import '../home/home_view.dart';
import '../home/task_glance.dart';
import '../side/agent_page.dart';
import '../ui/content/thread_page.dart';
import '../ui/controls/buttons.dart';
import '../ui/foundation/tokens.dart';
import 'canvas.dart';

BoardSection notchJourneysSection() => const BoardSection(
  title: 'Parcours · suivre une conversation dans son application',
  kind: FrameKind.play,
  note:
      'Simulation locale avec les vrais composants. Avancer représente un événement reçu de l’application source. '
      'Cliquer la tâche ouvre son fil, Accueil revient au notch. Aucun agent lancé, aucun message envoyé. '
      'La reprise est observée dans l’application source ; l’heure de fin de limite ne suffit pas à déclarer le travail repris.',
  frames: [BoardFrame(label: 'Travail → limite → reprise extérieure → fin', width: 700, child: NotchJourney())],
);

BoardSection notchInteractionMap() => const BoardSection(
  title: 'Carte des interactions · ce que la notch doit permettre',
  kind: FrameKind.trial,
  note:
      'Contrat de parcours pour finir la notch avant Discord/Paperclip. Une ligne décrit le résultat attendu ; '
      'sa présence ici ne vaut pas validation en réel. Le parcours ci-dessus et les demandes ci-dessous sont jouables.',
  frames: [
    BoardFrame(
      label: 'De l’observation au retour dans ton application',
      width: 700,
      child: BoardRules([
        (
          'Découvrir',
          'Ouvrir l’île au survol ou au raccourci ; distinguer aucun agent, activité et moteur déconnecté.',
        ),
        (
          'Suivre',
          'Voir la tâche active, son application, son état et ses sous-agents ; une activité observée ne garantit pas qu’un processus est vivant.',
        ),
        (
          'Naviguer',
          'Ouvrir la tâche ou une tuile, lire le fil, revenir à l’accueil ; paginer à la souris, molette et clavier.',
        ),
        (
          'Retrouver l’app',
          'Ouvrir l’application source pour continuer la conversation ; indiquer si sa fenêtre est introuvable.',
        ),
        (
          'Autoriser',
          'Lire toute la commande, Oui ou Non ; Plus tard laisse la demande ouverte ; une réponse dans l’app source la retire ici.',
        ),
        (
          'Répondre',
          'Choix simple, plusieurs choix, réponse libre, série de questions ; Précédente garde le brouillon ; Envoyer valide la sélection.',
        ),
        (
          'Différer',
          'Plus tard ne répond jamais à la question. Réouvrir la même demande ; vérifier aussi la conservation du brouillon après fermeture de l’île.',
        ),
        (
          'Reprendre',
          'Limite jaune → nouveau travail observé dans la même conversation → fin ; aucune reprise déclarée sur la seule échéance du quota.',
        ),
        (
          'Plusieurs agents',
          'Deux demandes simultanées restent indépendantes ; un sous-agent limité ne doit pas rebloquer un parent déjà repris.',
        ),
        (
          'Retrouver',
          'Historique, recherche, ouvrir une ancienne conversation ; une importation ne doit pas rejouer les sons de ses événements passés.',
        ),
        (
          'Régler',
          'Thème, sons, volume et position restent cohérents ; sons de lancement, limite, reprise et fin une seule fois par événement.',
        ),
        (
          'Reconnexion',
          'Perte du moteur, veille et redémarrage : afficher l’incertitude puis réconcilier l’état, sans dupliquer tâches, demandes ou sons.',
        ),
      ]),
    ),
  ],
);

/// Replays source events, rather than rendering unrelated screen snapshots.
class NotchJourney extends StatefulWidget {
  const NotchJourney({super.key});

  @override
  State<NotchJourney> createState() => _NotchJourneyState();
}

class _NotchJourneyState extends State<NotchJourney> {
  static final _at = DateTime(2026, 10, 16, 10);
  static const _steps = [
    'La conversation travaille dans Codex',
    'La limite arrête le tour',
    'Tu reprends dans Codex · Mikky reçoit le nouveau tour',
    'Le tour se termine · la conversation reste consultable',
  ];
  late SessionLog _log = _fresh();
  int _step = 0;
  bool _thread = false;
  String _reaction = 'État initial · aucun son de transition';

  SessionLog _fresh() => SessionLog()
    ..applyAll([
      SessionStarted('journey', app: AgentApp.codex, at: _at),
      TurnStarted(at: _at),
      UserMessage('Vérifie les tests du moteur', at: _at),
      ToolCallEvent('tests', title: 'Lance les tests', status: ToolStatus.running, at: _at),
    ]);

  void _next() => setState(() {
    final before = _log.statusAt(_log.lastEventAt!);
    _step++;
    switch (_step) {
      case 1:
        _log.apply(
          TurnEnded(
            StopReason.rateLimited,
            message: 'Usage limit reached. Try again in 2 hours.',
            at: _at.add(const Duration(minutes: 1)),
          ),
        );
      case 2:
        _log.applyAll([
          TurnStarted(at: _at.add(const Duration(hours: 2, minutes: 2))),
          UserMessage('Reprends les tests', at: _at.add(const Duration(hours: 2, minutes: 2))),
          ToolCallEvent(
            'retry',
            title: 'Relance les tests',
            status: ToolStatus.running,
            at: _at.add(const Duration(hours: 2, minutes: 2)),
          ),
        ]);
      case 3:
        _log.applyAll([
          const ToolCallEvent('retry', status: ToolStatus.completed),
          const AgentMessage('Les tests passent.'),
          TurnEnded(StopReason.endTurn, at: _at.add(const Duration(hours: 2, minutes: 3))),
        ]);
    }
    final cue = reactionTo(before, _log.statusAt(_log.lastEventAt!)).cue;
    _reaction = switch (cue) {
      MikkyCue.rateLimited => 'Réaction attendue : limite atteinte, une fois',
      MikkyCue.launch => 'Réaction attendue : reprise du travail, une fois',
      MikkyCue.finished => 'Réaction attendue : terminé, une fois',
      _ => 'Aucun nouveau son',
    };
  });

  void _reset() => setState(() {
    _log = _fresh();
    _step = 0;
    _thread = false;
    _reaction = 'État initial · aucun son de transition';
  });

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final status = _log.statusAt(_log.lastEventAt!);
    return SizedBox(
      width: 700,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_step + 1} / ${_steps.length} · ${_steps[_step]}', style: uiText(TextSize.label, color: ui.text)),
          const SizedBox(height: 10),
          HomeFrame(
            layout: HomeLayout.top,
            size: _thread ? HomeLayout.top.pageSize : null,
            child: _thread
                ? OwnOverlay(
                    child: AgentPageView(
                      model: AgentPageModel(
                        id: 'journey',
                        log: _log,
                        status: status,
                        external: true,
                        live: false,
                        canSend: false,
                      ),
                      actions: AgentPageActions(back: () => setState(() => _thread = false)),
                      mikky: MikkyBeside.middle,
                    ),
                  )
                : HomeView(
                    animate: false,
                    mikky: mikkyStateOf(status),
                    watched: WatchedTask(
                      id: 'journey',
                      name: 'Vérifie les tests du moteur',
                      log: _log,
                      status: status,
                      app: AgentApp.codex,
                    ),
                    onOpen: (_) => setState(() => _thread = true),
                  ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            children: [
              MButton(_step == 3 ? 'Parcours terminé' : 'Étape suivante', onPressed: _step < 3 ? _next : null),
              MButton(_thread ? 'Accueil' : 'Voir le fil', onPressed: () => setState(() => _thread = !_thread)),
              MButton('Rejouer', onPressed: _reset),
            ],
          ),
          const SizedBox(height: 8),
          Text(_reaction, style: uiText(TextSize.caption, color: ui.text3)),
        ],
      ),
    );
  }
}
