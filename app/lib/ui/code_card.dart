import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// One line of a [CodeCard]: its number, its text (spans for colors), and
/// whether it was removed or added.
class CodeLine {
  const CodeLine(this.number, this.spans, {this.removed = false, this.added = false});

  final int number;
  final List<InlineSpan> spans;
  final bool removed, added;
}

/// `.codecard`: the code the agent writes, live, under the step at work:
/// the file's name, then the changed lines (red removed, green added).
class CodeCard extends StatelessWidget {
  const CodeCard({super.key, required this.file, required this.lines});

  final String file;
  final List<CodeLine> lines;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final mono = uiText(10.5, mono: true, color: ui.text, height: 18 / 10.5);
    return Container(
      decoration: BoxDecoration(
        color: ui.well,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ui.line, strokeAlign: BorderSide.strokeAlignInside),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: ui.line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: ui.amber, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  file,
                  style: uiText(10.5, mono: true, weight: FontWeight.w500, color: ui.text2, height: 1.2),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final l in lines)
                  Container(
                    decoration: BoxDecoration(
                      color: l.removed ? ui.red.withValues(alpha: .1) : (l.added ? ui.green.withValues(alpha: .12) : null),
                      border: l.removed || l.added ? Border(left: BorderSide(color: l.removed ? ui.red : ui.green, width: 2)) : null,
                    ),
                    padding: EdgeInsets.only(right: 8, left: l.removed || l.added ? 0 : 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${l.number}',
                            textAlign: TextAlign.right,
                            style: mono.copyWith(color: ui.text3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: l.spans),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: l.removed ? mono.copyWith(color: ui.text2, decoration: TextDecoration.lineThrough) : mono,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
