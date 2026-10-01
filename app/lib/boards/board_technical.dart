import 'package:flutter/widgets.dart';

import '../ui/selectors.dart';
import '../ui/backend_status.dart';
import '../ui/tokens.dart';
import 'canvas.dart';

enum _Stage {
  ready('En place'),
  transition('À compléter'),
  next('Prévu'),
  measure('À mesurer');

  const _Stage(this.label);
  final String label;
  Color color(MikkyUi ui) => switch (this) {
    ready => ui.green,
    transition => ui.amber,
    next => ui.purple,
    measure => ui.blue,
  };
}

class _Badge extends StatelessWidget {
  const _Badge(this.stage);
  final _Stage stage;

  @override
  Widget build(BuildContext context) {
    final c = stage.color(MikkyUi.of(context));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, color: c),
        const SizedBox(width: 7),
        Text(
          stage.label,
          style: uiText(12, color: c, weight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.title, this.body, this.source, {this.stage = _Stage.ready, this.width = 310});
  final String title, body, source;
  final _Stage stage;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 2, color: stage.color(ui)),
          const SizedBox(height: 16),
          _Badge(stage),
          const SizedBox(height: 12),
          Text(
            title,
            style: uiText(20, color: ui.text, weight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(body, style: uiText(14, color: ui.text2, height: 1.55)),
          const SizedBox(height: 16),
          Text(source, style: uiText(11, mono: true, color: ui.text3, height: 1.5)),
        ],
      ),
    );
  }
}

class _Flow extends StatefulWidget {
  const _Flow();
  @override
  State<_Flow> createState() => _FlowState();
}

class _FlowState extends State<_Flow> {
  int _selected = 0;
  static const _steps = [
    (
      '01 / La demande',
      'Tu choisis Claude ou Codex, un dossier, Windows ou WSL et les permissions. Flutter transmet la demande ; Rust prépare la cible et lance la session.',
      'Flutter → AgentsService → RealAgentSource',
    ),
    (
      '02 / Le transport',
      'DaemonClient contacte mikkyd en WebSocket local. Les appels JSON-RPC demandent le lancement, l’ouverture de session puis l’envoi du message.',
      'tools.launch → run.open → run.prompt',
    ),
    (
      '03 / Le travail',
      'Le démon lance l’adaptateur ACP. Claude ou Codex réalise le travail avec ses propres outils et sa connexion ; Mikky ne contient pas de modèle IA.',
      'mikkyd → adaptateur ACP → Claude / Codex',
    ),
    (
      '04 / Ton accord',
      'En mode Demander, une permission reste en attente. Ton choix revient au démon, puis à l’agent. Les questions à choix ont leur propre réponse.',
      'run.answer / run.answerQuestion → ACP',
    ),
    (
      '05 / Le retour',
      'Rust traduit le trafic ACP en événements communs. SessionLog construit le fil côté Flutter ; l’île et sa petite fenêtre partagent le même moteur.',
      'Rust Reader → événements → SessionLog → interface',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final step = _steps[_selected];
    return SizedBox(
      width: 1030,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Segmented(
            options: const ['Demande', 'Transport', 'Travail', 'Permission', 'Retour'],
            selected: _selected,
            onChanged: (i) => setState(() => _selected = i),
          ),
          const SizedBox(height: 24),
          Text(
            step.$1,
            style: uiText(26, weight: FontWeight.w600, color: ui.text),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 750,
            child: Text(step.$2, style: uiText(16, color: ui.text2, height: 1.6)),
          ),
          const SizedBox(height: 20),
          Text(step.$3, style: uiText(13, mono: true, color: ui.blue)),
        ],
      ),
    );
  }
}

final technicalBoard = BoardSpec('Technique', 'Sous le capot · architecture, optimisations, suite', (context) {
  final ui = MikkyUi.of(context);
  return [
    const BoardSection(
      title: 'Connexion au moteur',
      note: 'États affichés dans l’application. Fermer Mikky laisse les agents du démon continuer ; « Arrêter tous les agents » est une action distincte.',
      frames: [
        SizedBox(
          width: 320,
          child: BackendStatus(
            title: 'Reconnexion en cours',
            message: 'Le dernier état reste visible. Les actions seront disponibles une fois la connexion rétablie.',
          ),
        ),
        SizedBox(
          width: 320,
          child: BackendStatus(
            title: 'Moteur indisponible',
            message: 'Le moteur ne répond pas. Nouvelle tentative automatique.',
            warning: true,
          ),
        ),
        SizedBox(
          width: 320,
          child: BackendStatus(
            title: 'Travail en arrière-plan',
            message: 'Fermer un écran laisse les agents et les permissions dans le moteur.',
            warning: true,
          ),
        ),
      ],
    ),
    BoardSection(
      title: 'Une petite île. Tout un moteur derrière.',
      note: 'Carte technique du 1er octobre 2026, issue du code et du plan mikkyd. Les statuts décrivent l’implémentation, pas une mesure en direct.',
      frames: [
        SizedBox(
          width: 1030,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Afficher. Orchestrer. Exécuter.',
                style: uiText(42, weight: FontWeight.w700, color: ui.text, tracking: -.03),
              ),
              const SizedBox(height: 16),
              Text(
                'Flutter donne vie à Mikky. Rust pilote les processus.\nClaude et Codex font le travail.',
                style: uiText(21, color: ui.text2, height: 1.5),
              ),
              const SizedBox(height: 28),
              Wrap(spacing: 28, children: [for (final s in _Stage.values) _Badge(s)]),
            ],
          ),
        ),
      ],
    ),
    const BoardSection(
      title: '01 — La carte du système',
      note: 'Chemin principal actuel. Les flèches représentent les commandes et les événements qui reviennent vers l’écran.',
      frames: [
        _Note(
          'L’interface',
          'Île, petite fenêtre, chat et planches. Flutter affiche les sessions et envoie tes actions. Le moteur Dart gère les états et les mouvements de Mikky.',
          'app/lib/\npackages/mikky_engine/',
          width: 280,
        ),
        Text('↔'),
        _Note(
          'Le chef d’orchestre',
          'mikkyd, en Rust, lance les processus, transmet les messages ACP et garde les permissions en attente. API locale JSON-RPC sur WebSocket.',
          'daemon/mikkyd/\ndaemon/mikky-acp/',
          width: 280,
        ),
        Text('↔'),
        _Note(
          'Les agents',
          'Claude Code et Codex, via leurs adaptateurs ACP, sous Windows ou WSL. Ils utilisent leurs outils et les connexions de tes abonnements.',
          'daemon/mikkyd/src/tools.rs',
          width: 280,
        ),
      ],
    ),
    const BoardSection(
      title: '02 — Suivre une demande',
      note: 'Clique sur une étape pour suivre son parcours. Exemple explicatif, sans lancer d’agent.',
      frames: [_Flow()],
    ),
    const BoardSection(
      title: '03 — Des responsabilités claires',
      frames: [
        _Note(
          'Un backend explicite',
          'Seul Rust prépare et lance les outils. En cas de déconnexion, les actions attendent la reconnexion. L’ancien réglage daemon et le mode --no-daemon ont été retirés de l’application.',
          'app/lib/agents/agents_service.dart',
          stage: _Stage.ready,
        ),
        _Note(
          'Les sessions extérieures',
          'Rust surveille les fichiers Windows et Linux avec des événements natifs. Il lit les octets ajoutés et normalise les transcriptions Claude et Codex. Flutter reçoit des pages de 256 événements.',
          'mikkyd · watch / session_reader',
          stage: _Stage.ready,
        ),
        _Note(
          'La vie après l’app',
          'Fermer l’interface laisse les agents et leurs permissions en attente dans le démon. La reconnexion reprend les messages manqués. Un arrêt global est une action séparée ; le démarrage Windows est réglable.',
          'AgentsService.shutdown\nmikkyd · autostart / linux',
          stage: _Stage.ready,
        ),
      ],
    ),
    const BoardSection(
      title: '04 — Dépenser moins, réagir juste',
      note: 'Mécanismes présents dans le code. Leur présence ne constitue pas un benchmark de la version actuelle.',
      frames: [
        _Note(
          '50 ms',
          'Les notifications du service sont regroupées : au plus une mise à jour toutes les 50 ms pendant le flux de texte, pour éviter une reconstruction à chaque fragment.',
          'AgentsService._changed',
        ),
        _Note(
          'Lire seulement la suite',
          'Le watcher Rust conserve un offset par fichier. La reconnexion ACP reprend après le dernier numéro reçu, par pages, sans dupliquer le fil. Les rafales de changements de fichier sont regroupées côté client.',
          'watch.rs · subscribe_page · DaemonSessionWatcher',
        ),
        _Note(
          'Réveiller au bon moment',
          'IslandMachine expose sa prochaine échéance. L’île programme ce réveil ; le contenu ouvert dispose d’une RepaintBoundary pour isoler son rendu.',
          'IslandMachine.nextDeadline\napp/lib/island/island_view.dart',
        ),
      ],
    ),
    const BoardSection(
      title: '05 — Mesurer avant de promettre',
      frames: [
        _Note(
          'Le budget graphique',
          'Profiler les flous superposés, les longues conversations et le markdown en release avec --perf. Observer les temps de frame avant de choisir les corrections.',
          'Plan mikkyd · optimisation de l’app',
          stage: _Stage.measure,
        ),
        _Note(
          'Le budget système',
          'Le backend est mesuré séparément. Reste à comparer l’application complète : île cachée, île animée, agents actifs et longues conversations sur la même machine.',
          'Mesures de charge à poursuivre',
          stage: _Stage.measure,
        ),
        _Note(
          '39 Mio · un premier relevé',
          'Backend Windows release, 25 historiques, aucun agent lancé : 39 Mio résidents, réponse locale p95 à 0,27 ms. Aucune hausse CPU relevée sur 5 s au repos. Lecture par blocs de 64 Kio.',
          '30 septembre · backend_perf.dart\nMesure locale, hors Flutter et WSL',
          stage: _Stage.measure,
        ),
      ],
    ),
    const BoardSection(
      title: '06 — Données & frontières de confiance',
      frames: [
        _Note(
          'Une porte locale',
          'Le WebSocket écoute sur 127.0.0.1. Son jeton est gardé dans le coffre Windows. Les connexions portant un en-tête Origin sont refusées.',
          'daemon/mikkyd/src/endpoint.rs\ndaemon/mikkyd/src/api.rs',
        ),
        _Note(
          'Ce qui reste sur le PC',
          'SQLite garde les métadonnées dans le backend ; les écritures passent par un thread dédié. agents.json est importé une seule fois et conservé. Les réglages visuels restent côté Flutter. Les outils gardent leurs transcriptions.',
          'mikky.db · settings.json · tuning.json',
          stage: _Stage.ready,
        ),
        _Note(
          'Le futur réseau',
          'Le PC relie déjà son démon au démon natif WSL par un pont local et un socket Unix privé. Restent à construire : VPS par SSH, identités de machines et canal entre agents avec droits et journal.',
          'Spec mikkyd · architecture cible',
          stage: _Stage.next,
        ),
      ],
    ),
    const BoardSection(
      title: '07 — Le bilan livré',
      note: 'Suivi du 1er octobre : main reste centré sur l’île. Où on en est : docs/superpowers/reprise.md.',
      frames: [
        _Note(
          'R2 → R3 / Le socle Rust',
          'Lancements, lecteurs et stockage appartiennent à Rust. L’ancien backend Dart est isolé dans les outils de test. Le protocole 3 diffuse les événements normalisés et synchronise les métadonnées des écrans.',
          'Parité vérifiée · app cliente uniquement',
          stage: _Stage.ready,
        ),
        _Note(
          'Données et continuité',
          'SQLite importe agents.json une seule fois. Les écrans partagent leurs métadonnées sans écraser les changements en attente. Permissions et questions survivent à la fermeture de l’écran ; WSL possède son moteur natif.',
          'Store · reconnexion · daemon WSL',
        ),
        _Note(
          'L’île au premier plan',
          'Le lancement ouvre à nouveau l’île et sa petite fenêtre. Grande fenêtre, entrée de menu et planche Espace retirées de main. Le backend et la planche Technique sont conservés.',
          '92c6be6 · Start-Mikky.ps1',
        ),
      ],
    ),
    const BoardSection(
      title: '08 — Vérifier et livrer',
      frames: [
        _Note(
          'Les contrôles passés',
          '14 tests Rust, 56 du client Dart, 111 du moteur d’affichage et 44 Flutter. Sept fixtures ACP comparées message par message. Scénario WSL : permission retrouvée après relance du pont Windows.',
          'Analyses sans problème · références clair/sombre',
        ),
        _Note(
          'Une livraison reproductible',
          'Scripts de build et de lancement, bundles versionnés, remplacement Linux atomique. Mise à jour des anciens moteurs seulement sans agent actif. Tâche de démarrage du moteur enregistrée dans Windows.',
          'scripts/Build-Windows.ps1 · autostart',
        ),
        _Note(
          'À confirmer en usage réel',
          'Tester une vraie reconnexion Windows et tout le parcours de l’île. Codex a répondu au smoke test ; la réponse complète de Claude WSL reste à revérifier après la limite de quota.',
          'Tâche enregistrée ≠ redémarrage testé',
          stage: _Stage.transition,
        ),
      ],
    ),
    const BoardSection(
      title: '09 — Les prochaines priorités de l’île',
      frames: [
        _Note(
          'Maîtriser la mémoire',
          'Charger les détails des historiques à la demande, garder des résumés et définir la conservation du flux. Les pages de 256 événements limitent les échanges, pas la mémoire totale du moteur.',
          'Historiques longs · nombreux agents',
          stage: _Stage.next,
        ),
        _Note(
          'Mesurer la fluidité',
          'Comparer CPU, mémoire et temps de frame : île au repos, animée, agents actifs et chat long. Profiler markdown et flous sur une même charge avant de choisir les optimisations.',
          'Release · Flutter + Rust + WSL',
          stage: _Stage.measure,
        ),
        _Note(
          'Relance après quota',
          'La relance automatique existe côté écran. Fermer cet écran suspend cette automatisation. Pour fonctionner sans interface, son échéancier devra rejoindre Rust avec des tests de reprise et d’annulation.',
          'Ensorcelé · pas encore durable côté Rust',
          stage: _Stage.transition,
        ),
      ],
    ),
    const BoardSection(
      title: '10 — Reporté et prévu pour plus tard',
      note: 'La grande fenêtre ne revient pas dans main sans nouvelle décision. La priorité reste l’île flottante.',
      frames: [
        _Note(
          'R4 / Grande fenêtre reportée',
          'Le prototype de monitoring, son cadre et la planche Espace sont sauvegardés sur une branche dédiée. Ils ne font plus partie de la version actuelle de Mikky.',
          'feature/r4-workspace · branche poussée',
          stage: _Stage.next,
        ),
        _Note(
          'R5 → R6 / Harnais et équipes',
          'Décrire les autres harnais et leurs capacités. Mener la recherche puis la spec des équipes : canal entre agents, identités, droits et journal avant implémentation.',
          'Descriptions → spec → intégration',
          stage: _Stage.next,
        ),
        _Note(
          'R7 → Après / Au-delà du PC',
          'Déployer mikkyd sur un VPS via SSH. Plus tard : routines, déclencheurs, téléphone et web. Le protocole et les contrôles d’accès devront accompagner chaque étape.',
          'VPS → automatisations → autres écrans',
          stage: _Stage.next,
        ),
      ],
    ),
  ];
});
