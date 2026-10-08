import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../motion/dot_waves.dart';
import '../motion/intro.dart';
import '../motion/launch.dart';
import '../motion/motion_player.dart';
import '../motion/pixel_power.dart';
import '../ui/motion.dart';
import '../ui/side.dart';
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

/// Everything about Mikky himself (2026-10-06: the Mouvement board renamed
/// « Mikky », with his drawing from the Marque board): his states, his
/// greeting, his arms, his powers; and the motion tools and effects they
/// are made with.
final mikkyBoard = BoardSpec(
  'Mikky',
  'Mikky lui-même : ses états, sa salutation, ses bras, ses pouvoirs ; et les outils du mouvement, à regarder au ralenti',
  (context) {
    final ui = MikkyUi.of(context);
    return [
    BoardSection(
      title: 'Ses états',
      note: 'Son vrai dessin, en petit, dans quelques états (l’île et l’écran de réglage les montrent tous).',
      frames: [
        BoardFrame(
          label: 'En petit',
          width: 560,
          child: Wrap(spacing: 22, runSpacing: 12, children: [
            for (final (st, name) in [
              (MikkyState.idle, 'repos'),
              (MikkyState.working, 'travaille'),
              (MikkyState.thinking, 'réfléchit'),
              (MikkyState.approval, 'attend'),
              (MikkyState.finished, 'terminé'),
              (MikkyState.sleeping, 'dort'),
            ])
              Column(mainAxisSize: MainAxisSize.min, children: [
                MiniMikky(size: 64, state: st),
                Text(name, style: uiText(TextSize.caption, color: ui.text3)),
              ]),
          ]),
        ),
      ],
    ),
    BoardSection(
      title: 'Le lancement',
      note: 'Sa salutation au démarrage de l’app (dans l’île, qui en est le fond) : une petite apparition, simple et souple, à la Disney / Pixar : sur un fond blanc, son ombre douce au sol ; l’anticipation, l’écrasement et l’étirement, des arcs, des oreilles qui suivent en retard. Lecture, ×0,25 pour le ralenti, la barre de temps pour aller à un instant ; dessous, ses moments et quelques courbes.',
      kind: FrameKind.app,
      frames: [
        for (final (c, note, curves, poster) in [
          (Intros.pop, 'Son ombre d’abord, puis il en jaillit, dépasse un peu sa taille et se pose, les yeux fermés ; il les ouvre. Puis sa magie, ultra rapide : il devient orange un instant, en 128 bits, tremble un peu, et une étoile éclate à côté de lui (un anneau, des étincelles en pixels). Puis il fait un petit saut content.', ['size', 'power', 'star', 'scaleY'], 1.65),
        ])
          BoardFrame(
            label: c.name,
            note: note,
            width: 520,
            child: MotionPlayer(choreography: c, curves: curves, poster: poster, scene: (context, t) => IntroScene(c, t)),
          ),
      ],
    ),
    BoardSection(
      title: 'Les bras · dodus',
      note: 'Gardés de tous les essais : des bras dodus, un bout rond et large sur une base plus fine, sortis de son contour sans jointure, comme ses oreilles. Des poses fixes seulement (« juste des keyframes ») : on les animera quand elles seront bonnes. Levé, un bras tourne depuis l’endroit où il pousse ; tendu, il s’allonge sans s’épaissir.',
      kind: FrameKind.trial,
      frames: [
        for (final pose in ArmPoses.all)
          BoardFrame(
            label: pose.name,
            width: 200,
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: PoseScene(pose, 0, size: const Size(200, 160), radius: 38)),
          ),
      ],
    ),
    BoardSection(
      title: 'Ses pouvoirs · en pixels',
      note: 'Notre direction pixel (les 16 et 32 bits étaient trop pixelisés) : Mikky en sprite fin quand il lance un sort, avec ses bras dodus, seize teintes tramées, une lumière le long de son bord, un halo en marches ; et en magicien, des étoiles et des étincelles en pixels. Nos deux couleurs signature, puis d’autres ; avec ses bras dodus, puis sans.',
      kind: FrameKind.trial,
      frames: [BoardFrame(label: '128 bits', child: _PixelPowerGrid())],
    ),
    BoardSection(
      title: 'Les ondes · réfléchir',
      note: 'D’après tes images d’une « vague de réflexion » : des points sur une petite grille, en notre bleu. L’onde, puis d’autres formes, en dégradé continu. Chacune en boucle, dans sa couche, sur l’horloge commune (30 images par seconde).',
      kind: FrameKind.trial,
      frames: [
        for (final w in DotWave.values.where((w) => !w.magic))
          BoardFrame(
            label: w.label,
            note: w.note,
            width: 176,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Looping(
                period: w.period,
                frozenAt: .3,
                builder: (context, t) => DotWaveScene(w, t * w.periodMs / 1000),
              ),
            ),
          ),
      ],
    ),
    BoardSection(
      title: 'Les ondes · maths et magie',
      note: 'Des courbes et des champs mathématiques, et un peu de magie, dans notre DA : la même grille de points, un dégradé plus étalé, du bleu nuit presque noir au blanc, qui remplit la grille.',
      kind: FrameKind.trial,
      frames: [
        for (final w in DotWave.values.where((w) => w.magic))
          BoardFrame(
            label: w.label,
            note: w.note,
            width: 176,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Looping(
                period: w.period,
                frozenAt: .3,
                builder: (context, t) => DotWaveScene(w, t * w.periodMs / 1000),
              ),
            ),
          ),
      ],
    ),
    BoardSection(
      title: 'Les courbes',
      note: 'Comment une valeur va d’un point à un autre (`Easings`, `SpringSpec`) : la courbe, et des points à intervalles de temps égaux, sur elle et sur une ligne dessous (serrés : lent ; écartés : rapide). Les ressorts sont ceux de l’app, joués exactement.',
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
            ('Performance', 'Le lecteur ne tourne que quand on appuie sur lecture, et jamais quand Windows demande moins d’animations ; pendant la lecture, seuls la scène et le curseur se redessinent, chacun dans sa couche. Chaque cadre des planches a sa couche, et les sprites en pixels sont dessinés une fois en image.'),
          ]),
        ),
      ],
    ),
  ];
  },
);

/// One curve, still: dots at equal times along it and along a line under
/// it show its pace (close: slow; apart: fast).
class _Curve extends StatelessWidget {
  const _Curve(this.ease);

  final Easing ease;

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(200, 120), painter: _CurvePainter(ease, MikkyUi.of(context)));
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.ease, this.ui);

  final Easing ease;
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
    final y = size.height - 8;
    canvas.drawLine(Offset(pad, y), Offset(pad + w, y), guide);
    final dot = Paint()..color = ui.blue;
    final move = Paint()..color = ui.text;
    for (var i = 0; i <= 10; i++) {
      final q = i / 10;
      canvas.drawCircle(at(q, ease(q)), 2.5, dot);
      canvas.drawCircle(Offset(pad + ease(q) * w, y), 3, move);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.ease != ease || old.ui != ui;
}

/// The pixel styles of his powers in rows, the colors in columns.
class _PixelPowerGrid extends StatelessWidget {
  const _PixelPowerGrid();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final label = uiText(TextSize.label, color: ui.text2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const SizedBox(width: 130),
          for (final (name, _) in PixelPowerColors.all) SizedBox(width: 174, child: Center(child: Text(name, style: label))),
        ]),
        const SizedBox(height: 6),
        for (final arms in const [true, false])
          for (final style in PixelPowerStyle.values)
            Padding(
              padding: EdgeInsets.only(bottom: 6, top: !arms && style == PixelPowerStyle.values.first ? 14 : 0),
              child: Row(children: [
                SizedBox(
                  width: 130,
                  child: Text(arms ? style.label : '${style.label}, sans les bras', style: uiText(TextSize.label, weight: FontWeight.w600, color: ui.text)),
                ),
                for (final (_, palette) in PixelPowerColors.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ClipRRect(borderRadius: BorderRadius.circular(10), child: PixelPowerScene(style, palette, arms: arms)),
                  ),
              ]),
            ),
      ],
    );
  }
}
