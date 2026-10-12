import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/enchant.dart';

import 'board_island_top.dart';
import 'canvas.dart';
import 'compact_preview.dart';

/// The closed island at the right edge, one agent in [status] (null: none).
class _Compact extends StatelessWidget {
  const _Compact(this.status, {this.detach = false});

  final AgentStatus? status;
  final bool detach;

  @override
  Widget build(BuildContext context) => CompactPreview(IslandEdge.right, switch (status) {
    null => CompactStars.empty,
    final s => fakeStars([(s, 0)], justFinished: s == AgentStatus.finished ? 0 : null),
  }, detach: detach);
}

final islandBoard = BoardSpec(
  'Petite île',
  'L’île fermée, en haut et à droite de l’écran, dans chaque état',
  (context) => [
    ...topIslandSections(),
    BoardSection(
      title: 'Dernier état et relance automatique',
      kind: FrameKind.trial,
      frames: [
        BoardFrame(
          label: 'Une ancienne limite, puis un agent au travail',
          note: 'Mikky suit le travail plus récent ; la limite reste dans les étoiles.',
          child: CompactPreview(IslandEdge.top, CompactStars.of(_recentStates)),
        ),
        BoardFrame(
          label: 'Relance automatique activée',
          note: 'Le jaune disparaît dès que la relance est planifiée ; Mikky suit l’autre agent.',
          child: CompactPreview(
            IslandEdge.top,
            CompactStars.of(Enchantments.instance.attentionAgents(_recentStates, scheduled: const {'limit'})),
          ),
        ),
      ],
    ),
    const BoardSection(
      title: 'Petite île à droite',
      note: 'Fermée : un petit onglet collé au bord droit, Mikky dans l’état de l’agent qu’il suit, et sous lui ce que fait cet agent (le même dessin que sur les lignes de l’accueil) ; son nom « Mikky », en Jacquard 24 (la police pixel du nom), quand il n’y a personne ou rien à montrer. Mikky travaille aussi quand l’agent réfléchit ou cherche (son animation de travail). Ce qui attend ton feu vert, ta réponse ou une erreur sort dans une bulle qui se détache de l’île, jamais sous Mikky. Survol : elle s’ouvre en petite fenêtre.',
      frames: [
        BoardFrame(label: 'Personne', note: 'Aucun agent : son nom.', child: _Compact(null)),
        BoardFrame(
          label: 'Travaille',
          note: 'Aussi quand il réfléchit ou cherche : le bleu.',
          child: _Compact(AgentStatus.working),
        ),
        BoardFrame(
          label: 'Attend ton feu vert',
          note: 'La bulle et son « ! » ; une question pareil.',
          child: _Compact(AgentStatus.approval),
        ),
        BoardFrame(label: 'Erreur', note: 'La bulle, « ! » rouge.', child: _Compact(AgentStatus.error)),
        BoardFrame(
          label: 'Limite atteinte',
          note: 'Le jaune, jusqu’à la reprise.',
          child: _Compact(AgentStatus.rateLimited),
        ),
        BoardFrame(
          label: 'Vient de finir',
          note: '5,2 s, puis l’agent suivant ; pas la grande île.',
          child: _Compact(AgentStatus.finished),
        ),
        BoardFrame(label: 'En pause', note: 'Rien ne bouge : son nom.', child: _Compact(AgentStatus.paused)),
      ],
    ),
    const BoardSection(
      title: 'La bulle',
      note: 'Elle sort du bas de l’onglet comme une goutte, gluante (les deux formes fondues l’une dans l’autre, sur un ressort), puis s’en détache ; le « ! » apparaît dedans. Clic sur la bulle : la page de l’agent.',
      frames: [
        BoardFrame(
          label: 'Se détache, revient',
          note: 'En boucle, sur le ressort de l’île.',
          child: _Compact(AgentStatus.approval, detach: true),
        ),
        BoardFrame(label: 'Erreur', child: _Compact(AgentStatus.error, detach: true)),
      ],
    ),
    const BoardSection(
      title: 'Fonctionnement',
      note: 'Ce que fait l’île, règle par règle (les valeurs sont celles du code : IslandTimings, IslandMachine).',
      frames: [
        BoardFrame(
          label: 'Règles de l’île',
          child: BoardRules([
            (
              'Quand elle sort',
              'Dès qu’un agent travaille, attend, est limité ou vient de finir. Personne : cachée, et aucune image (0 % de CPU). Pousser la souris contre le bord de l’écran fait sortir un aperçu.',
            ),
            (
              'Absent',
              '3 min sans bouger la souris : elle se cache, et revient au premier mouvement. Ce qui attend l’utilisateur la garde sortie.',
            ),
            ('Survol', 'Elle s’ouvre en 0,2 s ; la souris partie, elle se referme 0,65 s après.'),
            (
              'Clic',
              'Ouverte, elle reste jusqu’à 60 s sans rien faire ; un trait fin compte les 10 dernières secondes.',
            ),
            (
              'Clic en dehors',
              'Elle se referme, et ses menus flottants avec. S’il reste une alerte, la petite île garde sa bulle.',
            ),
            (
              'Alerte',
              'Feu vert, question ou erreur : la bulle sort d’abord (1,8 s), puis l’île s’ouvre sur l’agent, jusqu’à la réponse. Plusieurs alertes : l’une après l’autre, dans l’ordre.',
            ),
            (
              'Erreur',
              'Elle attend 30 min (sur l’île et dans « En attente »), puis devient une session finie en rouge.',
            ),
            ('Fini', 'La petite île sort 5,2 s, l’état « terminé » sous Mikky, puis l’agent quitte l’île.'),
            (
              'En haut',
              'Les étoiles des agents au milieu de la pilule, seulement le bleu et au-dessus, le jaune devant, la plus récente devant ; trois au plus, puis leur nombre au bout droit ; son nom collé à Mikky seulement sans étoile ; le vert seulement seul, ses 5,2 s. Feu vert, question, erreur : la bulle tombe du milieu, jamais dans la pile.',
            ),
            (
              'Qui Mikky suit',
              'Le dernier état actif reçu ; une ancienne limite ne le fige plus. Une demande ouverte garde son agent, et un agent qui vient de finir a ses 5,2 s. Une limite en relance automatique ne garde pas le jaune. Réfléchir et chercher, c’est travailler.',
            ),
            (
              'Sessions d’ailleurs',
              'Un terminal ou VS Code : elles comptent dès qu’elles bougent pendant que Mikky regarde. Les vieilles ne remontent pas sur l’île au démarrage.',
            ),
            (
              'Performance',
              '60 images par seconde pendant les mouvements, 30 au repos (Mikky respire), aucune quand elle est cachée.',
            ),
          ]),
        ),
      ],
    ),
  ],
);

const _recentStates = [
  Agent(id: 'limit', name: 'Ancienne limite', status: AgentStatus.rateLimited, startedAt: 0, statusSince: 1),
  Agent(id: 'work', name: 'Dernier agent', status: AgentStatus.working, startedAt: 0, statusSince: 2),
];
