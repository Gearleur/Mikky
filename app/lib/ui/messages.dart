import 'package:flutter/widgets.dart';

import 'markdown.dart';
import 'tokens.dart';

/// A chat bubble (`.msg`, `.bub`): the user's in ink on the right, the
/// agent's grey on the left; the corner towards the speaker is sharper.
class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.me, required this.child, this.thread = false});

  final bool me;
  final Widget child;

  /// In the metro line the agent's corner is at the top (`.msg-it .bub`).
  final bool thread;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    const big = Radius.circular(20), small = Radius.circular(8);
    final radius = me
        ? const BorderRadius.only(topLeft: big, topRight: big, bottomLeft: big, bottomRight: small)
        : (thread
              ? const BorderRadius.only(topLeft: small, topRight: big, bottomLeft: big, bottomRight: big)
              : const BorderRadius.only(topLeft: big, topRight: big, bottomLeft: small, bottomRight: big));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(color: me ? ui.ink : ui.well, borderRadius: radius),
      child: DefaultTextStyle(
        style: uiText(14, color: me ? ui.onInk : ui.text, height: 1.4),
        child: child,
      ),
    );
  }
}

/// A chat message with its line of meta (`.msg` + `.mmeta`). The user's
/// is a bubble, 84 % wide at most; the agent's has no bubble and takes the
/// whole width, as chat apps do (user request, 2026-09-30).
class ChatMessage extends StatelessWidget {
  const ChatMessage({super.key, required this.me, required this.text, this.meta});

  final bool me;
  final String text;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final metaLine = meta == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Text(meta!, style: uiText(11, color: ui.text3, height: 1.3)),
          );
    if (!me) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 2, 2, 2),
            child: DefaultTextStyle(style: uiText(14, color: ui.text, height: 1.5), child: AgentText(text)),
          ),
          ?metaLine,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FractionallySizedBox(
          widthFactor: .84,
          alignment: Alignment.centerRight,
          child: Align(alignment: Alignment.centerRight, child: Bubble(me: true, child: Text(text))),
        ),
        ?metaLine,
      ],
    );
  }
}
