import 'package:flutter/widgets.dart';

import '../ui/motion.dart';
import '../ui/selectors.dart';
import '../ui/side.dart';
import '../ui/tokens.dart';
import 'board_brand.dart';
import 'board_components.dart';
import 'board_screens.dart';
import 'canvas.dart';

/// `mikky.exe --kit`: the design boards, as in Figma (user request,
/// 2026-09-30): the brand, the components once each, and every screen of
/// the small window in each of its states, live (they move, they can be
/// clicked). Light, dark, or both. Development tool, like the tuning
/// screen.
class BoardsApp extends StatelessWidget {
  const BoardsApp({super.key, this.performance = false});

  /// `--perf`: Flutter's frame graphs on top.
  final bool performance;

  @override
  Widget build(BuildContext context) => WidgetsApp(
    title: 'Planches de Mikky',
    color: MikkyUi.light.board,
    debugShowCheckedModeBanner: false,
    showPerformanceOverlay: performance,
    builder: (context, _) => const Boards(),
  );
}

final boards = [brandBoard, componentsBoard, homeBoard, agentBoard, messagesBoard];

class Boards extends StatefulWidget {
  const Boards({super.key, this.initial = 0, this.themes = 0});

  final int initial;

  /// 0: light, 1: dark, 2: both.
  final int themes;

  @override
  State<Boards> createState() => _BoardsState();
}

class _BoardsState extends State<Boards> {
  late int _board = widget.initial;
  late int _themes = widget.themes;
  final _canvas = GlobalKey<BoardCanvasState>();
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    const shell = MikkyUi.light;
    final spec = boards[_board];
    final bands = [if (_themes != 1) MikkyUi.light, if (_themes != 0) MikkyUi.dark];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final ui in bands) BoardBand(spec: spec, ui: ui)],
    );
    return MikkyUiTheme(
      ui: shell,
      child: DefaultTextStyle(
        style: uiText(14, color: shell.text),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(
              selected: _board,
              onSelect: (i) {
                setState(() => _board = i);
                _canvas.currentState?.reset();
              },
              themes: _themes,
              onThemes: (i) => setState(() => _themes = i),
            ),
            Container(width: 1, color: shell.line),
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: BoardCanvas(
                    key: _canvas,
                    background: bands.first.board,
                    onScale: (s) => setState(() => _scale = s),
                    child: KeyedSubtree(key: ValueKey((_board, _themes)), child: content),
                  ),
                ),
                Positioned(right: 16, bottom: 16, child: ZoomPill(canvas: _canvas, scale: _scale)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// One board in one theme: its name, then its sections.
class BoardBand extends StatelessWidget {
  const BoardBand({super.key, required this.spec, required this.ui});

  final BoardSpec spec;
  final MikkyUi ui;

  @override
  Widget build(BuildContext context) => MikkyUiTheme(
    ui: ui,
    child: Container(
      color: ui.board,
      padding: const EdgeInsets.fromLTRB(40, 36, 80, 20),
      child: DefaultTextStyle(
        style: uiText(15, color: ui.text),
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(spec.name, style: uiText(30, weight: FontWeight.w700, color: ui.text, tracking: -.02)),
                const SizedBox(width: 14),
                Text(ui.isLight ? 'Clair · île blanc pur' : 'Sombre · île noir A', style: uiText(14, color: ui.text3)),
              ]),
              const SizedBox(height: 36),
              ...spec.sections(context),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect, required this.themes, required this.onThemes});

  final int selected;
  final ValueChanged<int> onSelect;
  final int themes;
  final ValueChanged<int> onThemes;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: 260,
      color: ui.island,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const HeadMikky(),
            Text('Planches', style: uiText(17, weight: FontWeight.w600, color: ui.text)),
          ]),
          const SizedBox(height: 18),
          for (var i = 0; i < boards.length; i++)
            HoverBuilder(
              builder: (context, hover) => MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: i == selected ? ui.well : (hover ? ui.hover : null),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(boards[i].name, style: uiText(14, weight: i == selected ? FontWeight.w600 : FontWeight.w500, color: ui.text)),
                      Text(boards[i].note, maxLines: 2, style: uiText(11.5, color: ui.text3, height: 1.35)),
                    ]),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Text('Molette : défiler · Maj : de côté · Ctrl : zoom · glisser le fond : déplacer', style: uiText(11, color: ui.text3, height: 1.4)),
          const SizedBox(height: 12),
          Segmented(options: const ['Clair', 'Sombre', 'Les deux'], selected: themes, size: SegmentSize.xs, onChanged: onThemes),
        ],
      ),
    );
  }
}
