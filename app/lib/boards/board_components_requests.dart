import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../side/question_card.dart';
import '../ui/content/diff_lines.dart';
import '../ui/content/diff_view.dart';
import '../ui/controls/step_tabs.dart';
import '../ui/foundation/tokens.dart';
import '../ui/pixels/dot_surface.dart';
import '../ui/pixels/pixel_fx.dart';
import 'board_components.dart';
import 'board_notch_requests.dart';
import 'canvas.dart';
import 'fake_sessions.dart';

/// The shared request components, including the actual home notch.
(String, List<Widget>) requestComponents() => (
  'Demandes',
  [
    BoardSection(
      title: 'Demandes',
      note: 'Les composants de l’app : à l’échelle du notch en haut (700 × 200), puis dans la page d’un agent. Même liseré, mêmes réponses, couleurs adaptées au thème.',
      frames: [
        const BoardFrame(label: 'Notch · feu vert', kind: FrameKind.play, width: 700, child: NotchRequestDemo()),
        const BoardFrame(
          label: 'Notch · question',
          kind: FrameKind.play,
          width: 700,
          child: NotchRequestDemo(question: true),
        ),
        const BoardFrame(
          label: 'Notch · répondre dans l’app',
          width: 700,
          child: NotchRequestDemo(question: true, readOnly: true),
        ),
        BoardFrame(
          label: 'Une question',
          note: 'Le liseré, les onglets, les choix à plat ; « Précédente », « Tout passer », « Suivante » ou « Envoyer ».',
          child: Tray([
            QuestionCard(
              question: FakeSessions.questions().question!,
              trial: const QuestionTrial(answers: {'db': 'SQLite'}),
              onAnswer: (_) {},
            ),
          ], width: 460),
        ),
        const BoardFrame(
          label: 'Le liseré de ce qui t’attend',
          note: 'PixelEdge.waiting : trois colonnes de points à travers nos oranges, plein en haut, qui s’égrène vers le bas, glitché en tranches. Il se met le long de ce qui attend une réponse.',
          child: Tray([_Waiting()]),
        ),
        BoardFrame(
          label: 'Les étapes en onglets',
          note: 'StepTabs : celle où l’on est, un carré de pixels orange ; les faites, une coche dans nos bleus (un clic y revient) ; les suivantes en gris.',
          child: Tray([
            Local<int>(
              1,
              (at, go) => StepTabs(
                labels: const ['Base', 'Quand', 'Journal'],
                at: at,
                done: {for (var i = 0; i < at; i++) i},
                onSelect: go,
              ),
            ),
          ]),
        ),
        const BoardFrame(
          label: 'La surface à points',
          note: 'DotSurface, comme Nothing : la couleur de la fenêtre — blanche à points gris très clairs en clair, noire à points pâles en sombre —, un point tous les 6 px, un trait fin. Pour du code.',
          child: Tray([_Code()]),
        ),
        const BoardFrame(
          label: 'Les lignes d’un diff',
          note: 'DiffLineRow et DiffFoldRow sur la surface à points : numérotées, ajoutées dans nos bleus, retirées dans nos oranges, un grain de pixels à côté du numéro (PixelEdge.change) ; DiffCount aux mêmes couleurs.',
          child: Tray([_Lines()], width: 460),
        ),
      ],
    ),
  ],
);

/// A question's mark beside a question and its choices.
class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quelle base de données ?',
                style: uiText(TextSize.body, weight: FontWeight.w600, color: ui.text),
              ),
              const SizedBox(height: 6),
              for (final choice in ['SQLite', 'Postgres', 'Aucune pour l’instant'])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(choice, style: uiText(TextSize.label, color: ui.text)),
                ),
            ],
          ),
        ),
        Positioned(left: 0, top: 4, bottom: 4, child: PixelEdge.waiting(ui)),
      ],
    );
  }
}

/// A few lines of code on the surface of dots.
class _Code extends StatelessWidget {
  const _Code();

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return DotSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Text(
        'void main() {\n  runApp(const Mikky());\n}',
        style: uiText(TextSize.caption, mono: true, color: ui.text, height: 18 / TextSize.caption),
      ),
    );
  }
}

/// A file's change, a few of its lines.
class _Lines extends StatelessWidget {
  const _Lines();

  static const _lines = [
    DiffLine(DiffOp.same, '  final double Function() now;', oldLine: 7, newLine: 7),
    DiffLine(DiffOp.removed, '  static const autoCloseSec = 60.0;', oldLine: 9),
    DiffLine(DiffOp.added, '  /// The spec’s delay: 45 s after the last click.', newLine: 9),
    DiffLine(DiffOp.added, '  static const autoCloseSec = 45.0;', newLine: 10),
    DiffLine(DiffOp.same, '  static const countdownSec = 10.0;', oldLine: 10, newLine: 11),
  ];

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'island_machine.dart',
              style: uiText(TextSize.heading, weight: FontWeight.w600, color: ui.text),
            ),
            const SizedBox(width: 10),
            const DiffCount(added: 2, removed: 1, size: TextSize.label),
          ],
        ),
        const SizedBox(height: 10),
        DiffFoldRow(count: 6, first: true, left: DiffLineRow.codeAt(2), onTap: () {}),
        for (final (i, line) in _lines.indexed)
          DiffLineRow(line, last: i == _lines.length - 1, run: line.op == DiffOp.added ? (i - 2, 2) : (0, 1)),
      ],
    );
  }
}
