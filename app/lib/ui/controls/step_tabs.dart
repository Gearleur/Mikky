import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../foundation/motion.dart';
import '../foundation/tokens.dart';
import '../pixels/pixel_fx.dart';

/// Where a step is (2026-10-12, the questions of a form).
enum StepState { done, current, todo }

/// One step's mark, 10 px, in pixels (2026-10-12; user: « les ticks
/// validés, mets-les en bleu », « utilise plusieurs bleus »): the one
/// shown, a little square of 3 × 3 pixels in our oranges, lit from its top
/// left; a done one, a pixel tick in our blues, light at its tip, deep at
/// its foot; one to come, a grey pixel. [lit]: under the mouse, a tint
/// lighter.
class StepMark extends StatelessWidget {
  const StepMark(this.state, {super.key, this.lit = false});

  final StepState state;
  final bool lit;

  static const size = 10.0;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final blue = PixelFxPalette.signatureBlue.onWindow(ui).levels;
    return CustomPaint(
      size: const Size.square(size),
      painter: _MarkPainter(
        state,
        orange: PixelFxPalette.signatureOrange.onWindow(ui),
        done: lit ? blue.take(3).toList() : blue.skip(1).toList(),
        todo: lit ? ui.text : ui.text3,
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.state, {required this.orange, required this.done, required this.todo});

  final StepState state;
  final PixelFxPalette orange;

  /// The tick's three blues, from its tip to its foot.
  final List<Color> done;
  final Color todo;

  /// A tick on 5 × 4 pixels of 2 px, and which of its blues each takes.
  static const _tick = [(4, 0, 0), (3, 1, 0), (2, 2, 1), (0, 2, 2), (1, 3, 2)];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    switch (state) {
      case StepState.current:
        // 3 × 3 pixels of 2 px, 1 px apart: light at the top left, deep at
        // the bottom right.
        for (var y = 0; y < 3; y++) {
          for (var x = 0; x < 3; x++) {
            paint.color = orange.levels[x + y == 0 ? 0 : (x + y == 4 ? 2 : 1)];
            canvas.drawRect(Rect.fromLTWH(1 + x * 3.0, 1 + y * 3.0, 2, 2), paint);
          }
        }
      case StepState.done:
        for (final (x, y, tint) in _tick) {
          paint.color = done[tint];
          canvas.drawRect(Rect.fromLTWH(x * 2.0, 1 + y * 2.0, 2, 2), paint);
        }
      case StepState.todo:
        paint.color = todo;
        canvas.drawRect(const Rect.fromLTWH(4, 4, 2, 2), paint);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.state != state || old.orange != orange || !listEquals(old.done, done) || old.todo != todo;
}

/// Where we are among steps, like tabs (2026-10-12, the questions of a
/// form; chosen: « on garde les onglets »): each one's [StepMark], then
/// its label — the one shown in black, the done ones grey, the next ones
/// pale. A click on a done one, or on the first to come, goes there.
/// Still: nothing loops.
class StepTabs extends StatelessWidget {
  const StepTabs({super.key, required this.labels, required this.at, required this.done, this.onSelect});

  final List<String> labels;
  final int at;
  final Set<int> done;
  final ValueChanged<int>? onSelect;

  int get count => labels.length;

  StepState _state(int i) => i == at
      ? StepState.current
      : done.contains(i)
      ? StepState.done
      : StepState.todo;

  /// A done one, or the first to come — never the one shown.
  bool _can(int i) {
    if (onSelect == null || i == at) return false;
    if (done.contains(i)) return true;
    for (var k = 0; k < count; k++) {
      if (!done.contains(k)) return k == i;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Semantics(
      label: '${at + 1} sur $count',
      child: Wrap(
        spacing: 16,
        runSpacing: 2,
        children: [
          for (var i = 0; i < count; i++) ...[
            HoverBuilder(
              enabled: _can(i),
              builder: (context, hover) {
                final lit = hover && _can(i);
                final state = _state(i);
                final mark = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StepMark(state, lit: lit),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: uiText(
                          TextSize.small,
                          weight: state == StepState.current ? FontWeight.w600 : FontWeight.w500,
                          color: lit || state == StepState.current
                              ? ui.text
                              : (state == StepState.done ? ui.text2 : ui.text3),
                        ),
                      ),
                    ),
                  ],
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _can(i) ? () => onSelect!(i) : null,
                  child: MouseRegion(
                    cursor: _can(i) ? SystemMouseCursors.click : MouseCursor.defer,
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: mark),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
