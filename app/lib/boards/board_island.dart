import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../island/compact_view.dart';
import '../island/island_painter.dart';
import 'canvas.dart';

/// The island's shader, loaded once for the boards (null: its plain
/// fallback, as when the graphics driver cannot compile it).
final Future<ui.FragmentProgram?> _program = loadIslandProgram();

/// The closed island at the right edge, with the shader once it is there.
class _Compact extends StatelessWidget {
  const _Compact(this.status, {this.detach = false, this.jacquard = false});

  final AgentStatus? status;
  final bool detach, jacquard;

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.FragmentProgram?>(
    future: _program,
    builder: (context, shot) => CompactIslandPreview(status: status, program: shot.data, detach: detach, jacquard: jacquard),
  );
}

final islandBoard = BoardSpec('Petite île', 'L’île fermée, à droite de l’écran, dans chaque état', (context) => [
  const BoardSection(
    title: 'Petite île à droite',
    note: 'Fermée : un petit onglet collé au bord droit, Mikky dans l’état de l’agent qu’il suit, et sous lui ce que fait cet agent (le même dessin que sur les lignes de l’accueil) ; son nom « Mikky » quand il n’y a personne ou rien à montrer. Ce qui attend ton feu vert, ta réponse ou une erreur sort dans une bulle qui se détache de l’île, jamais sous Mikky. Survol : elle s’ouvre en petite fenêtre.',
    frames: [
      BoardFrame(label: 'Personne', note: 'Aucun agent : son nom.', child: _Compact(null)),
      BoardFrame(label: 'Travaille', note: 'Aussi quand il réfléchit ou cherche : le bleu.', child: _Compact(AgentStatus.working)),
      BoardFrame(label: 'Attend ton feu vert', note: 'La bulle et son « ! » ; une question pareil.', child: _Compact(AgentStatus.approval)),
      BoardFrame(label: 'Erreur', note: 'La bulle, « ! » rouge.', child: _Compact(AgentStatus.error)),
      BoardFrame(label: 'Limite atteinte', note: 'Le jaune, jusqu’à la reprise.', child: _Compact(AgentStatus.rateLimited)),
      BoardFrame(label: 'Vient de finir', note: '5,2 s, puis l’agent suivant ; pas la grande île.', child: _Compact(AgentStatus.finished)),
      BoardFrame(label: 'En pause', note: 'Rien ne bouge : son nom.', child: _Compact(AgentStatus.paused)),
    ],
  ),
  const BoardSection(
    title: 'La bulle',
    note: 'Elle sort du bas de l’onglet comme une goutte, gluante (les deux formes fondues l’une dans l’autre, sur un ressort), puis s’en détache ; le « ! » apparaît dedans. Clic sur la bulle : la page de l’agent.',
    frames: [
      BoardFrame(label: 'Se détache, revient', note: 'En boucle, sur le ressort de l’île.', child: _Compact(AgentStatus.approval, detach: true)),
      BoardFrame(label: 'Erreur', child: _Compact(AgentStatus.error, detach: true)),
    ],
  ),
  const BoardSection(
    title: 'Le nom en Jacquard 24 (essai)',
    note: 'La police pixel du nom de l’app, sur la petite île, à côté de Geist (l’actuel).',
    frames: [
      BoardFrame(label: 'Geist (actuel)', child: _Compact(null)),
      BoardFrame(label: 'Jacquard 24', child: _Compact(null, jacquard: true)),
      BoardFrame(label: 'Jacquard 24, en pause', child: _Compact(AgentStatus.paused, jacquard: true)),
    ],
  ),
]);
