import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/foundation/motion.dart';
import 'canvas.dart';
import 'compact_preview.dart';

// The closed island at the top (2026-10-12, trial): its states, its bubble,
// and a scene that goes through them, for the « Petite île » board.

CompactPreview _top(CompactStars stars, {bool detach = false}) => CompactPreview(IslandEdge.top, stars, detach: detach);

const _w = AgentStatus.working, _t = AgentStatus.thinking, _s = AgentStatus.searching;
const _l = AgentStatus.rateLimited, _f = AgentStatus.finished, _p = AgentStatus.paused;
const _a = AgentStatus.approval, _q = AgentStatus.question, _e = AgentStatus.error;

/// The sections of the closed island at the top.
List<Widget> topIslandSections() => [
  BoardSection(
    title: 'Petite île en haut',
    note: 'La version de droite, allongée en haut (dans l’app depuis le 12 octobre) : la pilule de 186 × 36 collée au haut de l’écran ; Mikky au début, dans l’état de l’agent qu’il suit, au milieu les étoiles d’état des agents, superposées — seulement le bleu et au-dessus (au travail, réfléchit, cherche ; la limite en jaune devant), la plus récente devant ; le vert d’un agent qui vient de finir seulement quand il est seul, ses 5,2 s. Chaque étoile découpe une marge d’un pixel dans celles de derrière, et garde son propre rythme. Au-delà de trois, leur nombre collé au bout droit. Son nom, collé à Mikky (Jacquard 24), seulement quand il n’y a aucune étoile.',
    frames: [
      BoardFrame(label: 'Personne', note: 'Son nom.', child: _top(CompactStars.empty)),
      BoardFrame(
        label: 'Travaille',
        note: 'Une étoile bleue au milieu ; son nom s’efface.',
        child: _top(fakeStars([(_w, 0)])),
      ),
      BoardFrame(
        label: 'Deux au travail',
        note: 'Superposées, la plus récente à gauche, dessus.',
        child: _top(fakeStars([(_w, 0), (_t, 1)])),
      ),
      BoardFrame(
        label: 'Trois au travail',
        note: 'Chacune à son rythme ; réfléchir et chercher, c’est travailler.',
        child: _top(fakeStars([(_w, 0), (_t, 1), (_s, 2)])),
      ),
      BoardFrame(
        label: 'Limite atteinte',
        note: 'Le jaune passe devant le bleu.',
        child: _top(fakeStars([(_w, 1), (_l, 0)])),
      ),
      BoardFrame(
        label: 'Vraiment plein',
        note: 'Sept agents : trois étoiles, leur nombre collé au bout droit.',
        child: _top(fakeStars([for (var i = 0; i < 6; i++) (_w, i.toDouble()), (_l, 0)])),
      ),
      BoardFrame(
        label: 'Vient de finir, seul',
        note: 'Le vert, figé, ses 5,2 s ; Mikky fait son saut content.',
        child: _top(fakeStars([(_f, 0), (_p, 0)], justFinished: 0)),
      ),
      BoardFrame(
        label: 'Vient de finir, d’autres travaillent',
        note: 'Pas de vert : seulement le bleu et au-dessus ; Mikky fait quand même son saut.',
        child: _top(fakeStars([(_f, 2), (_w, 0), (_w, 1)], justFinished: 0)),
      ),
      BoardFrame(label: 'En pause', note: 'Rien ne bouge : son nom.', child: _top(fakeStars([(_p, 0)]))),
    ],
  ),
  BoardSection(
    title: 'La bulle, en haut',
    note: 'Le feu vert, une question ou une erreur ne va jamais dans les étoiles : l’orange ou le rouge prend leur place et tombe du milieu de la pilule dans une bulle gluante (les deux formes fondues l’une dans l’autre, sur le ressort de l’île), puis s’en détache ; le « ! » dedans. Plusieurs alertes : la première (feu vert et questions, puis erreurs, la plus ancienne d’abord) et combien attendent. Les étoiles des autres restent dans la pilule. Clic sur la bulle : la page de l’agent, pour répondre.',
    frames: [
      BoardFrame(
        label: 'Attend ton feu vert',
        note: 'Seul : son nom dans la pilule, la bulle tombe et revient, en boucle.',
        child: _top(fakeStars([(_a, 0)]), detach: true),
      ),
      BoardFrame(
        label: 'D’autres travaillent',
        note: 'Leurs étoiles restent ; la bulle tombe du milieu, sous elles.',
        child: _top(fakeStars([(_a, 2), (_w, 0), (_w, 1)]), detach: true),
      ),
      BoardFrame(label: 'Erreur', note: 'Le « ! » rouge.', child: _top(fakeStars([(_e, 1), (_w, 0)]))),
      BoardFrame(
        label: 'Plusieurs alertes',
        note: 'La première, et combien attendent.',
        child: _top(fakeStars([(_e, 0), (_a, 1), (_q, 2), (_w, 0), (_l, 0)])),
      ),
      const BoardFrame(
        label: 'Scène',
        kind: FrameKind.play,
        note: 'Tout s’enchaîne, en boucle (24 s) : des agents arrivent, la pile se remplit, le nombre ; un feu vert puis une erreur tombent dans la bulle ; la réponse, la bulle remonte et l’étoile revient ; des agents finissent, le dernier en vert. Ici l’île reste fermée pour voir la bulle ; dans l’app, elle s’ouvre sur la demande 1,8 s après.',
        child: _TopScene(),
      ),
    ],
  ),
];

/// One moment of [_TopScene]: from [at] seconds, these agents.
typedef _Beat = ({double at, List<(String, AgentStatus, double)> agents, String? justFinished});

/// The closed island at the top through a made-up day, in a loop: the
/// bubble on its spring, the stars coming, going and sliding.
class _TopScene extends StatefulWidget {
  const _TopScene();

  /// When animations are off (and on the goldens): two alerts out, a full
  /// pile.
  static const still = 9.0;

  static const length = 24.0;

  static final List<_Beat> beats = [
    (at: 0, agents: [], justFinished: null),
    (at: 1, agents: [('a', _w, 1)], justFinished: null),
    (at: 2.4, agents: [('a', _w, 1), ('b', _w, 2.4)], justFinished: null),
    (at: 3.6, agents: [('a', _w, 1), ('b', _w, 2.4), ('c', _l, 3.6)], justFinished: null),
    (at: 5, agents: [('a', _w, 1), ('b', _w, 2.4), ('c', _l, 3.6), ('d', _t, 5), ('e', _s, 5.2)], justFinished: null),
    (at: 7, agents: [('a', _w, 1), ('b', _a, 7), ('c', _l, 3.6), ('d', _t, 5), ('e', _s, 5.2)], justFinished: null),
    (at: 8.4, agents: [('a', _w, 1), ('b', _a, 7), ('c', _l, 3.6), ('d', _e, 8.4), ('e', _s, 5.2)], justFinished: null),
    (at: 11, agents: [('a', _w, 1), ('b', _w, 11), ('c', _l, 3.6), ('d', _e, 8.4), ('e', _s, 5.2)], justFinished: null),
    (at: 13, agents: [('a', _w, 1), ('b', _w, 11), ('c', _l, 3.6), ('e', _s, 5.2)], justFinished: null),
    (at: 14.5, agents: [('a', _w, 1), ('b', _w, 11), ('c', _w, 14.5), ('e', _f, 14.5)], justFinished: 'e'),
    (at: 16, agents: [('a', _f, 16), ('b', _w, 11), ('c', _w, 14.5)], justFinished: 'a'),
    (at: 17.5, agents: [('b', _w, 11), ('c', _f, 17.5)], justFinished: 'c'),
    (at: 18.5, agents: [('b', _f, 18.5)], justFinished: 'b'),
    (at: 23.7, agents: [], justFinished: null),
  ];

  static CompactStars starsAt(double t) {
    final beat = beats.lastWhere((b) => b.at <= t);
    return CompactStars.of([
      for (final (id, s, at) in beat.agents) Agent(id: id, name: id, status: s, startedAt: 0, statusSince: at),
    ], justFinished: beat.justFinished);
  }

  @override
  State<_TopScene> createState() => _TopSceneState();
}

class _TopSceneState extends State<_TopScene> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _bubble = Spring(0, SpringSpec.sideBubble);
  Duration _last = Duration.zero;
  double _time = 0;

  /// The last alert in the bubble: it goes back in with it once answered.
  AgentStatus? _alert;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = Motion.loops(context);
    if (run && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _last = elapsed;
    setState(() {
      _time = (_time + dt) % _TopScene.length;
      final head = _TopScene.starsAt(_time).alerts.firstOrNull;
      _alert = head?.status ?? _alert;
      _bubble.target = head == null ? 0 : 1;
      _bubble.step(dt);
    });
  }

  @override
  Widget build(BuildContext context) {
    final run = _ticker.isActive;
    final stars = _TopScene.starsAt(run ? _time : _TopScene.still);
    return CompactPreview(
      IslandEdge.top,
      stars,
      out: run ? _bubble.value : (stars.alerts.isEmpty ? 0 : 1),
      answered: _alert,
    );
  }
}
