import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../motion/launch.dart';
import '../motion/motion_player.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart';
import 'canvas.dart';

/// The curves we animate with, each seen as a curve and as a dot moving
/// along it.
final _curves = <(String, String, Easing)>[
  ('out', 'Arrive en douceur : ce qui entre.', Easings.out),
  ('inOut', 'Part et arrive en douceur : ce qui va d’un endroit à un autre.', Easings.inOut),
  ('inCubic', 'Accélère : une chute, un départ.', Easings.inCubic),
  ('outQuint', 'Très vite puis très doux : un geste vif.', Easings.outQuint),
  ('back', 'Dépasse un peu et revient : ce qui pop.', Easings.back),
  ('Ressort de l’île', '165 / 0,74 : sec, à peine un rebond.', Easings.spring(SpringSpec.island, .7)),
  ('Ressort de la goutte', '120 / 0,42 : gluant, il oscille.', Easings.spring(SpringSpec.drop, 1.1)),
  ('Ressort de Mikky qui glisse', '60 / 0,9 : flottant, lent.', Easings.spring(SpringSpec.glideAcross, 1.2)),
];

final motionBoard = BoardSpec(
  'Mouvement',
  'Les outils du mouvement, à regarder au ralenti : chorégraphies, ressorts, courbes, particules, et les essais qui s’en servent',
  (context) => [
    BoardSection(
      title: 'Le lancement',
      note: 'Quand Mikky démarre : l’île sort du haut de l’écran, Mikky y arrive, dit coucou, et ils repartent. Trois essais, chacun une chorégraphie écrite à la main (comme la salutation de Mochi) : la barre de temps va à n’importe quel instant (clic ou glisser), ×0,25 pour le ralenti ; sous la barre, ses moments et les courbes de quelques pistes.',
      kind: FrameKind.trial,
      frames: [
        for (final (c, note, curves) in [
          (Launches.fall, 'Il tombe du haut de l’écran avec des traînées, atterrit écrasé dans un anneau de poussière, rebondit, regarde à gauche et à droite, coucou des oreilles.', ['ih', 'y', 'scaleY', 'yaw']),
          (Launches.hatch, 'Une petite boule de poils arrive en tournant, tremble, et éclot en Mikky parmi trois petits feux d’artifice ; il ouvre les yeux, ses oreilles sortent l’une après l’autre, coucou avec un saut.', ['furball', 'scaleY', 'open', 'earLeft']),
          (Launches.arms, 'Il grimpe depuis le bas de l’île : les oreilles, puis les yeux, il regarde ; ses mains s’accrochent au bord, il se hisse, et fait coucou de la main (bras souples).', ['y', 'arms', 'handRightY', 'handRightX']),
        ])
          BoardFrame(
            label: c.name,
            note: note,
            width: 520,
            child: MotionPlayer(
              choreography: c,
              curves: curves,
              poster: c.at('coucou')! + .35,
              scene: (context, t) => LaunchScene(c, t),
            ),
          ),
      ],
    ),
    BoardSection(
      title: 'Les bras · cinq dessins',
      note: 'Des bras plutôt que des pattes (« les pattes sont moches ») : cinq dessins, qui font la même chose. Ils sortent de ses côtés, font coucou, montrent la tâche, youpi, et rentrent dans son corps ; d’un seul contour avec lui, invisibles quand ils sont rentrés.',
      kind: FrameKind.trial,
      frames: [
        for (final style in ArmStyle.values)
          BoardFrame(
            label: ArmLoops.names[style]!,
            note: ArmLoops.notes[style],
            width: 300,
            child: MotionPlayer(
              choreography: ArmLoops.tour,
              width: 300,
              poster: 1.5,
              scene: (context, t) => PoseScene(ArmLoops.tour, t, size: const Size(300, 180), arms: style),
            ),
          ),
      ],
    ),
    BoardSection(
      title: 'Les bras · côte à côte',
      note: 'Les cinq dessins, figés aux mêmes instants, pour comparer.',
      kind: FrameKind.trial,
      frames: [BoardFrame(label: 'Les cinq dessins', child: _ArmGrid())],
    ),
    BoardSection(
      title: 'Les courbes',
      note: 'Comment une valeur va d’un point à un autre (`Easings`, `SpringSpec`) : la courbe, et un point qui la suit. Les ressorts sont ceux de l’app, joués exactement.',
      frames: [
        for (final (name, note, ease) in _curves) BoardFrame(label: name, note: note, width: 200, child: _Curve(ease)),
      ],
    ),
    const BoardSection(
      title: 'Fonctionnement',
      note: 'Comment on fait une animation, maintenant.',
      frames: [
        BoardFrame(
          label: 'Une chorégraphie',
          child: BoardRules([
            ('Une fonction du temps', 'Une animation est une `Choreography` : des pistes nommées (la taille de l’île, la place de Mikky, ses oreilles, ses bras…), chacune une suite de temps forts (`Beat` : à tel instant, telle valeur, par telle courbe). Rien ne tourne tout seul : on peut montrer n’importe quel instant, ralentir, revenir.'),
            ('Les moments', 'Des repères nommés (`Mark`) : « atterrit », « coucou »… On y accroche un son ou des particules, et ils s’affichent sur la barre de temps.'),
            ('Les ressorts', '`Easings.spring` joue un ressort exactement (ses rebonds et son arrêt) sur une durée donnée, pour qu’il ait sa place dans une chorégraphie.'),
            ('Les particules', '`Burst` : des étincelles tirées au sort une fois (graine fixe), donc les mêmes à chaque fois, avec leur freinage et leur gravité ; on dessine n’importe quel instant.'),
            ('Mikky posé', '`MikkyGeometry.posed` dessine Mikky dans la pose qu’on lui donne, sans sa vie propre (clignements, souffle) : la chorégraphie décide de tout.'),
            ('Performance', 'Le lecteur ne tourne que pendant la lecture, et pas du tout quand Windows demande moins d’animations : il montre alors un instant fixe.'),
          ]),
        ),
      ],
    ),
  ],
);

/// One curve, and a dot going along it, again and again.
class _Curve extends StatelessWidget {
  const _Curve(this.ease);

  final Easing ease;

  @override
  Widget build(BuildContext context) => Looping(
        period: const Duration(milliseconds: 2200),
        frozenAt: .45,
        builder: (context, t) => CustomPaint(size: const Size(200, 120), painter: _CurvePainter(ease, (t * 1.4).clamp(0.0, 1.0), MikkyUi.of(context))),
      );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.ease, this.q, this.ui);

  final Easing ease;
  final double q;
  final MikkyUi ui;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 14.0;
    final w = size.width - pad * 2, h = size.height - pad * 2 - 14;
    Offset at(double x, double y) => Offset(pad + x * w, pad + 6 + h - y * h);
    final guide = Paint()
      ..color = ui.line
      ..strokeWidth = 1;
    canvas.drawLine(at(0, 0), at(1, 0), guide);
    canvas.drawLine(at(0, 1), at(1, 1), guide);
    final path = Path();
    for (var i = 0; i <= 100; i++) {
      final p = at(i / 100, ease(i / 100));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = ui.text2);
    canvas.drawCircle(at(q, ease(q)), 4, Paint()..color = ui.blue);
    // The same value, as a move from left to right, under it.
    final y = size.height - 8;
    canvas.drawLine(Offset(pad, y), Offset(pad + w, y), guide);
    canvas.drawCircle(Offset(pad + ease(q) * w, y), 4.5, Paint()..color = ui.text);
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.q != q || old.ui != ui;
}

/// The arm styles in rows, the same instants in columns.
class _ArmGrid extends StatelessWidget {
  const _ArmGrid();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final label = uiText(TextSize.label, color: ui.text2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const SizedBox(width: 110),
          for (final (name, _) in ArmLoops.stills) SizedBox(width: 160, child: Center(child: Text(name, style: label))),
        ]),
        const SizedBox(height: 6),
        for (final style in ArmStyle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 110, child: Text(ArmLoops.names[style]!, style: label)),
              for (final (_, t) in ArmLoops.stills)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: PoseScene(ArmLoops.tour, t, size: const Size(156, 120), arms: style, radius: 26),
                  ),
                ),
            ]),
          ),
      ],
    );
  }
}
