import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/enchant.dart';
import '../side/session_cards.dart';
import '../side/session_text.dart';
import '../side/session_views.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/cards.dart';
import '../ui/feedback.dart';
import '../ui/field.dart';
import '../ui/icons.dart';
import '../ui/messages.dart';
import '../ui/pixel_fx.dart';
import '../ui/selectors.dart';
import '../ui/side.dart';
import '../ui/sliding_hover.dart';
import '../ui/status.dart';
import '../ui/tasks.dart';
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
    this.paused = const [],
    this.done = const [],
    this.history = 0,
    this.limits,
    this.historyOpen = false,
    this.limited = const [],
    this.autoRelaunch = false,
    this.calm = false,
  });

  /// Pared down (trial): quiet group titles, no « WSL », short times.
  final bool calm;

  /// « Relance automatique » on (the home's ··· menu): the violet star
  /// after « Agents ».
  final bool autoRelaunch;

  /// Stopped by their limit, with the ones at work; true: already under
  /// the spell (« Ensorceler »).
  final List<(SampleRow, bool)> limited;

  final List<SampleRow> waiting;
  final List<(SampleRow, UiStatus)> working;

  /// Put on hold: with the ones at work, « Reprendre » on the card.
  final List<SampleRow> paused;
  final List<SampleRow> done;
  final int history;
  final String? limits;
  final bool historyOpen;

  @override
  State<HomeMock> createState() => _HomeMockState();
}

class _HomeMockState extends State<HomeMock> {
  late final _open = {'wait': true, 'work': true, 'done': true, 'old': widget.historyOpen};

  // The spells of the limited rows, as the app's agents would have.
  late final _ids = [for (var i = 0; i < widget.limited.length; i++) 'board-home-${identityHashCode(this)}-$i'];
  final _log = FakeSessions.limited();

  @override
  void initState() {
    super.initState();
    for (final (i, (_, spell)) in widget.limited.indexed) {
      if (spell) Enchantments.instance.enchant(_ids[i], _log.limitResetsAt, (_) async {}, now: _log.lastEventAt);
    }
  }

  @override
  void dispose() {
    for (final id in _ids) {
      Enchantments.instance.cancel(id);
    }
    super.dispose();
  }

  /// Where it runs, unless pared down.
  String _who(String w) => widget.calm ? '' : w;

  /// « Il y a 14 min » → « 14 min » when pared down.
  String _when(String s) => widget.calm ? s.replaceFirst('Il y a ', '') : s;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final body = <Widget>[];
    void group(String id, String label, Color color, UiStatus? status, int n, List<Widget> rows) {
      if (n == 0) return;
      body.add(GroupHeader(
        quiet: widget.calm,
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
          who: _who(w),
          brand: b,
          subtitle: s,
          style: AgentCardStyle.waiting,
          onTap: () {},
          onMenu: () {},
          actions: WaitActions(command: 'npm run build', onYes: () {}, onNo: () {}),
        ),
    ]);
    group('work', 'Travaillent', ui.blue, UiStatus.working, widget.working.length + widget.paused.length + widget.limited.length, [
      for (final ((t, b, s, w), st) in widget.working) AgentCard(status: st, title: t, who: _who(w), brand: b, subtitle: s, onTap: () {}, onMenu: () {}),
      for (final (i, ((t, b, _, w), _)) in widget.limited.indexed)
        LimitedAgentCard(id: _ids[i], title: t, log: _log, send: (_) async {}, who: w, brand: b, onTap: () {}, onMenu: () {}, onFinish: () {}),
      for (final (t, b, _, w) in widget.paused)
        AgentCard(
          status: UiStatus.paused,
          title: t,
          who: w,
          brand: b,
          subtitle: 'En pause',
          onTap: () {},
          onMenu: () {},
          actions: Align(alignment: Alignment.centerRight, child: AnswerBar(answers: [('Reprendre', () {})])),
        ),
    ]);
    group('done', 'Terminés', ui.green, UiStatus.finished, widget.done.length, [
      for (final (t, b, s, w) in widget.done)
        AgentCard(status: UiStatus.finished, title: t, who: _who(w), brand: b, subtitle: _when(s), style: AgentCardStyle.done, onTap: () {}, onMenu: () {}),
    ]);
    group('old', 'Historique', ui.grey, null, widget.history, [
      for (final (t, w) in [('Ajoute la position à droite', 'Claude'), ('Traduis le README', 'Codex'), ('Corrige le hook souris', 'Claude')])
        AgentCard(status: UiStatus.finished, title: t, who: w, style: AgentCardStyle.old, onTap: () {}, onMenu: () {}),
    ]);
    // At the top, as in the app (2026-10-01).
    if (widget.limits != null) body.insert(0, SubscriptionLimits([(Brand.codex, widget.limits!)]));
    return SideFrame(
      child: Stack(children: [
        SideHead(
          title: 'Agents',
          titleMark: AutoRelaunchMark(force: widget.autoRelaunch),
          leading: const HeadMikky(),
          actions: [RoundButton.menu(size: 34, onPressed: () {})],
        ),
        Positioned.fill(
          top: 68,
          child: body.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(32, 120, 32, 0),
                  child: Column(children: [
                    Text('Aucun agent pour l’instant', textAlign: TextAlign.center, style: uiText(TextSize.body, weight: FontWeight.w500, color: ui.text2)),
                    const SizedBox(height: 6),
                    Text('La flèche en bas lance Claude ou Codex.', textAlign: TextAlign.center, style: uiText(TextSize.small, color: ui.text3)),
                  ]),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 72),
                  child: SlidingHover(radius: 14, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body)),
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
  (('Prépare le plan de l’API', Brand.codex, 'Réfléchit au plan', ''), UiStatus.working),
];
const _workingOne = (('Corrige les tests du moteur', Brand.claude, 'Modifie island_machine.dart', ''), UiStatus.working);
const _paused = ('Prépare le plan de l’API', Brand.codex, '', '');
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
      BoardFrame(
        label: 'Un agent en pause',
        note: 'Avec ceux qui travaillent : gris, « En pause », Reprendre sur la carte.',
        child: HomeMock(working: [_workingOne], paused: [_paused]),
      ),
      BoardFrame(label: 'Tout à la fois', note: 'Attend, travaillent, terminés, historique replié.', child: HomeMock(waiting: [_waiting], working: _working, done: _done, history: 12)),
      BoardFrame(
        label: 'Limite atteinte, ensorcelé',
        note: 'Étoile jaune : la limite, et quand elle se lève ; « Terminer » (on n’attend plus, l’agent passe dans Terminés) ou « Relance auto ». Ensorcelé : une ligne normale, qui dit quand il se relance, et « Terminer » pour refuser la relance. Étoile violette après « Agents » : la relance automatique pour tous, dans le menu ··· de l’accueil.',
        child: HomeMock(
          autoRelaunch: true,
          working: [_workingOne],
          limited: [
            (('Traduis la documentation', Brand.claude, '', ''), false),
            (('Nettoie les imports', Brand.codex, '', 'WSL'), true),
          ],
        ),
      ),
      BoardFrame(
        label: 'Limites Codex en haut, historique ouvert',
        note: 'Les limites de l’abonnement en haut, avant les groupes (1er octobre ; avant : tout en bas).',
        child: HomeMock(working: [_workingOne], done: _done, history: 12, historyOpen: true, limits: '69 % des 5 h, repart à 17 h 10 · 70 % de la semaine'),
      ),
      BoardFrame(
        label: 'Limite Codex atteinte',
        note: 'Codex écrit 99 % juste avant de refuser : bloqué, Mikky affiche 100 % jusqu’à la reprise, et la tâche en « Limite atteinte » (plus « Terminé »).',
        child: HomeMock(
          limited: [(('Nettoie les imports', Brand.codex, '', ''), false)],
          done: _done,
          limits: '100 % des 5 h, repart à 14 h 10 · 74 % de la semaine',
        ),
      ),
    ],
  ),
  const BoardSection(
    title: 'Accueil épuré (essai)',
    note: 'Un peu moins d’information : le feu d’artifice seulement pour « En attente » et « Travaillent », les titres en gris, le chevron au survol ; les logos tournent quand l’agent travaille, sautillent quand il attend. Plus de « WSL », des heures courtes.',
    frames: [
      BoardFrame(label: 'Tout à la fois, actuel', child: HomeMock(waiting: [_waiting], working: _working, done: _done, history: 12)),
      BoardFrame(label: 'Tout à la fois, épuré', child: HomeMock(waiting: [_waiting], working: _working, done: _done, history: 12, calm: true)),
    ],
  ),
  const BoardSection(
    title: 'Fonctionnement',
    note: 'Ce que fait l’accueil, règle par règle.',
    frames: [
      BoardFrame(
        label: 'Règles de l’accueil',
        child: BoardRules([
          ('En attente', 'Feu vert et questions (on répond sur la ligne), erreurs de moins de 30 min.'),
          ('Travaillent', 'Au travail, en pause (« Reprendre »), arrêtés par la limite (« Terminer », « Relance auto »).'),
          ('Terminés, Historique', 'Les 5 plus récents de moins d’un jour ; le reste dans l’historique, replié. Archives : rangées à la main.'),
          ('Ordre', 'Les épinglés en tête de leur groupe ; sinon le plus récent d’abord.'),
          ('Limites Codex', 'En haut : ce qui reste sur 5 h et sur la semaine (Claude ne le donne pas). Bloqué après le dernier relevé : 100 % jusqu’à la reprise.'),
          ('Terminer', 'Sur une limite : on n’attend plus ; la session passe dans Terminés et quitte l’île. Elle revient si elle bouge de nouveau.'),
          ('Relance auto', 'Mikky envoie « reprends » une minute après la reprise (30 min si l’heure est inconnue). Ensorcelé, il reste dans Travaillent, avec « Terminer » pour refuser. Pour tous : réglage du menu étoile, étoile violette après « Agents ».'),
          ('Erreur réglée', 'Menu de la ligne, « Marquer l’erreur comme réglée » : elle passe dans Terminés.'),
          ('Menu d’une ligne', 'Étoile grise ou clic droit : pause, arrêter, VS Code, dossier, renommer, épingler, archiver, supprimer (la confirmation reprend le même panneau).'),
          ('Sessions d’ailleurs', 'Lancées dans un terminal ou VS Code, elles apparaissent seules. Une reprise (« fork ») remplace l’originale.'),
        ]),
      ),
    ],
  ),
]);

// ----------------------------------------------------------------- agent

/// An agent's page in its window, fed by a made-up session (the same
/// Suivi and Chat as the app's).
class AgentMock extends StatefulWidget {
  const AgentMock({
    super.key,
    required this.title,
    required this.log,
    this.chat = false,
    this.external = false,
    this.adapterPid,
    this.scrolled = false,
    this.paused = false,
    this.enchanted = false,
    this.finished = false,
  });

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

  /// Starts on Chat (else Suivi, while it works).
  final bool chat;

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
  late int _view = widget.chat ? 1 : 0;
  late final _scroll = ScrollController(initialScrollOffset: widget.scrolled ? 120 : 0);

  // Its own agent id for the spell, as the app's page would have.
  late final _id = 'board-${identityHashCode(this)}';
  late final _limit = LimitHooks(_id, (_) async {}, finish: () {}, finished: widget.finished);

  @override
  void initState() {
    super.initState();
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
    final suivi = working && _view == 0;
    final usage = usageLine(log);
    final content = <Widget>[
      if (widget.adapterPid != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('Adaptateur ACP · PID ${widget.adapterPid} · Windows', style: uiText(11.5, color: ui.text3, tabular: true)),
        ),
      if (usage.isNotEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10), child: Text(usage, style: uiText(TextSize.caption, color: ui.text3, tabular: true))),
      ...(suivi ? suiviOf(context, log) : chatOf(context, log, toSuivi: () => setState(() => _view = 0), limit: _limit)),
      if (widget.paused)
        Padding(padding: const EdgeInsets.only(top: 12), child: PausedCard(onResume: () {}))
      else if (log.question != null)
        Padding(padding: const EdgeInsets.only(top: 12), child: QuestionCard(question: log.question!, onAnswer: (_) {}))
      else if (log.pending.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 12), child: AskCard(log: log, onAnswer: (_) {})),
    ];
    final readOnly = widget.external && working;
    return SideFrame(
      child: Stack(children: [
        // As the app: no title, the thread up to the top, the buttons over it.
        Positioned.fill(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(16, 62, 16, readOnly ? 56 : (working ? 96 : 78)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content),
          ),
        ),
        // Softer on top (user request, 2026-09-30: « trop puissant »).
        const Positioned(top: 0, left: 0, right: 0, child: TopBlur()),
        // Only behind the field, not above it (user request, 2026-09-30).
        Positioned(left: 0, right: 0, bottom: 0, child: EdgeBlur(top: false, height: readOnly ? 44 : (working ? 74 : 54))),
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
            child: Composer(
              glass: true,
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
              Expanded(child: Text('Session extérieure : activité observée, processus non vérifié.', style: uiText(TextSize.caption, color: ui.text3, height: 1.35))),
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

final agentBoard = BoardSpec('Agent', 'La page d’un agent : Suivi, Chat, attentes, fins', (context) => [
  BoardSection(
    title: 'Au travail',
    note: 'Suivi (la ligne de métro) ou Chat, au choix sous le champ. Pas de titre ni de bandeau : le fil va jusqu’en haut, les boutons flottent dessus (retour ; « ··· », le menu : mettre en pause ou reprendre, arrêter l’agent, VS Code, dossier, renommer, épingler, archiver, supprimer).',
    frames: [
      BoardFrame(label: 'Suivi', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.working(), adapterPid: 12345)),
      BoardFrame(label: 'Chat, avec un plan', child: AgentMock(title: 'Corrige les tests du moteur', log: FakeSessions.working(), chat: true)),
      BoardFrame(
        label: 'Chat, sans plan',
        note: 'Les outils regroupés en grandes lignes, colorées par action.',
        child: AgentMock(title: 'Ajoute un test Codex', log: FakeSessions.workingNoPlan(), chat: true),
      ),
      BoardFrame(
        label: 'Session hors de Mikky',
        note: 'Lancée ailleurs : Mikky lit son activité, sans confirmer que son processus tourne et sans pouvoir lui répondre.',
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
                  trailing: Text('+12', style: uiText(TextSize.caption, weight: FontWeight.w500, mono: true, color: ui.green)),
                ),
                const NoteLine('Résumé écrit, 12 lignes.'),
              ],
            ),
          ]),
        ),
        BoardFrame(
          label: 'Arrêtée, en erreur',
          child: _Pane([
            const TaskSection(status: UiStatus.paused, title: 'Tâche arrêtée', meta: '2 étapes', steps: [TaskStep(label: 'Lit 2 fichiers')]),
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
