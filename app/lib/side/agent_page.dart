import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/buttons.dart';
import '../ui/field.dart';
import '../ui/icons.dart';
import '../ui/motion.dart';
import '../ui/selection.dart';
import '../ui/selectors.dart';
import '../ui/side.dart';
import '../ui/tokens.dart';
import 'session_menu.dart';
import 'session_views.dart';
import 'side_app.dart';

/// An agent's page (UX `ux-a.html`). While it works: Suivi (the metro
/// line) or Chat (the whole conversation), the choice half inside the
/// field. Once done: the plain chat, the work folded in « Tâche terminée »
/// cards, and the conversation goes on. Sessions started elsewhere are
/// followed without touching them; once done they can go on in Mikky.
class AgentPage extends StatefulWidget {
  const AgentPage({super.key, required this.host, required this.id, required this.back, this.rename});

  final SideHost host;
  final String id;
  final VoidCallback back;

  /// Opens the rename page for this session.
  final VoidCallback? rename;

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  /// 0: Suivi, 1: Chat.
  int _view = 0;
  final _scroll = ScrollController();
  int _lastVersion = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  RealAgentSource get _source => widget.host.service.source;

  void _send(String text) {
    _source.send(widget.id, text);
    // The answer comes in the chat: follow it.
    if (!(_source.entry(widget.id)?.log.working ?? false)) setState(() => _view = 1);
  }

  /// In Chat, stays at the bottom as the conversation grows (unless the
  /// user scrolled up to read).
  void _follow(SessionLog log) {
    if (log.version == _lastVersion) return;
    // Opening the page: straight to the end of the conversation.
    final first = _lastVersion == -1;
    _lastVersion = log.version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      if (first || p.maxScrollExtent - p.pixels < 160) _scroll.jumpTo(p.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final e = _source.entry(widget.id);
    if (e == null) {
      return Stack(
        children: [
          SideHead(
            title: 'Agent',
            small: true,
            leading: RoundButton('left', size: 34, onPressed: widget.back, tooltip: 'Retour'),
          ),
        ],
      );
    }
    final log = e.log;
    final working = log.working;
    final external = e.origin == AgentOrigin.external;
    final suivi = working && _view == 0;
    if (!suivi) _follow(log);

    final usage = usageLine(log);
    final content = <Widget>[
      if (usage.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(usage, style: uiText(11.5, color: ui.text3, tabular: true)),
        ),
      ...(suivi ? suiviOf(context, log) : chatOf(context, log, toSuivi: () => setState(() => _view = 0))),
      if ((log.pending.isNotEmpty || log.question != null) && e.live)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: log.question != null
              ? QuestionCard(question: log.question!, onAnswer: (answers) => _source.answerQuestion(e.id, answers))
              : AskCard(log: log, onAnswer: (a) => widget.host.answer(e.id, a)),
        ),
    ];

    final Widget? composer = external && working
        ? null
        : Composer(
            key: ValueKey('composer:${e.id}'),
            placeholder: working
                ? 'Écris à cet agent…'
                : external
                ? 'Continuer dans Mikky…'
                : 'Continuer avec cet agent…',
            options: working
                ? Segmented(options: const ['Suivi', 'Chat'], selected: _view, size: SegmentSize.field, onChanged: (i) => setState(() => _view = i))
                : null,
            commands: e.live ? log.commands : const [],
            onSend: _send,
            glass: true,
          );

    // No title, no band on top: the thread goes up to the top as it
    // scrolls, the buttons float over it (user request, 2026-09-30).
    return Stack(
      children: [
        // The thread fills the page and passes under the buttons and the
        // field, blurred (user request, 2026-09-30).
        Positioned.fill(
          child: SingleChildScrollView(
            controller: _scroll,
            // Room for the field, or for the read-only note of outside sessions.
            padding: EdgeInsets.fromLTRB(16, 62, 16, composer == null ? 56 : (working ? 104 : 78)),
            child: SelectableArea(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: Motion.reduced(context) ? 1 : 220),
                switchInCurve: Motion.enter,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, .02), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                child: Column(
                  key: ValueKey(suivi),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (content.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: Center(
                          child: Text('Rien à montrer', style: uiText(13, color: ui.text3)),
                        ),
                      ),
                    ...content,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Softer on top (user request, 2026-09-30: « trop puissant »).
        const Positioned(top: 0, left: 0, right: 0, child: TopBlur()),
        // Only behind the field, not above it (user request, 2026-09-30).
        Positioned(left: 0, right: 0, bottom: 0, child: EdgeBlur(top: false, height: composer == null ? 44 : (working ? 82 : 54))),
        SideHead(
          leading: RoundButton('left', size: 34, onPressed: widget.back, tooltip: 'Retour'),
          actions: [
            if (e.live && working) RoundButton('stop', size: 34, onPressed: () => _source.cancel(e.id), tooltip: 'Arrêter l’agent'),
            RoundButton(
              'more',
              size: 34,
              tooltip: 'Plus',
              onPressed: () => showSessionMenu(widget.host, e, rename: widget.rename ?? () {}, deleted: widget.back),
            ),
          ],
        ),
        if (composer != null) Positioned(left: 20, right: 20, bottom: 12, child: composer),
        if (composer == null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Row(
              children: [
                MikkyIcon('lock', size: 13, color: ui.text3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ouverte dans VS Code ou un terminal : Mikky la suit sans y toucher.',
                    style: uiText(11.5, color: ui.text3, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
