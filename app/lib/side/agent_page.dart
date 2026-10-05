import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/buttons.dart';
import '../ui/cards.dart';
import '../ui/field.dart';
import '../ui/icons.dart';
import '../ui/side.dart';
import '../ui/thread_page.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'session_cards.dart';
import 'session_menu.dart';
import 'session_text.dart';
import 'session_views.dart';
import 'side_app.dart';

/// An agent's page in the app: [AgentPageView] fed by the agent Mikky
/// follows, its actions sent to the agent.
class AgentPage extends StatelessWidget {
  const AgentPage({super.key, required this.host, required this.id, required this.back, this.rename, this.mikky});

  final SideHost host;
  final String id;
  final VoidCallback back;

  /// Mikky's place beside the thread (the notch: in the middle); the
  /// island draws him there.
  final MikkyBeside? mikky;

  /// Opens the rename page for this session.
  final VoidCallback? rename;

  RealAgentSource get _source => host.service.source;

  @override
  Widget build(BuildContext context) {
    final e = _source.entry(id);
    if (e == null) {
      return Stack(children: [
        SideHead(title: 'Agent', small: true, leading: RoundButton('left', size: 34, onPressed: back, tooltip: 'Retour')),
      ]);
    }
    final hook = _source.hookAskOf(e.id);
    return AgentPageView(
      key: ValueKey(e.id),
      mikky: mikky,
      drawMikky: false,
      model: AgentPageModel(
        id: e.id,
        log: e.log,
        status: e.status,
        external: e.origin == AgentOrigin.external,
        live: e.live,
        host: e.host,
        adapterPid: e.live && e.run is DaemonAgentRun ? (e.run as DaemonAgentRun).adapterPid : null,
        hook: hook == null ? null : (description: hook.description, request: hook.request),
        limitFinished: e.status == AgentStatus.rateLimited && e.homeStatus == AgentStatus.finished,
        canSend: host.service.canLaunch,
      ),
      actions: AgentPageActions(
        back: back,
        send: (text) => _source.send(e.id, text),
        answer: (a) => host.answer(e.id, a),
        answerQuestion: (answers) => _source.answerQuestion(e.id, answers),
        resume: () => _source.unpause(e.id),
        finishLimit: () => finishLimit(host, e.id),
        unfinishLimit: () => _source.unsettle(e.id),
        menu: () => showSessionMenu(host, e, rename: rename ?? () {}, deleted: back),
      ),
    );
  }
}

/// What an agent's page shows: read from its agent in the app, made up on
/// the boards — one page for both (2026-10-05: the boards show the app's
/// own screens, never a copy).
class AgentPageModel {
  const AgentPageModel({
    required this.id,
    required this.log,
    required this.status,
    this.external = false,
    this.live = true,
    this.host = AgentHost.windows,
    this.adapterPid,
    this.hook,
    this.limitFinished = false,
    this.canSend = true,
  });

  final String id;
  final SessionLog log;
  final AgentStatus status;

  /// Started in VS Code or a terminal: followed, read only while it works.
  final bool external;

  /// Launched by Mikky and still running: it can answer.
  final bool live;
  final AgentHost host;

  /// PID of the ACP adapter Mikky runs for it.
  final int? adapterPid;

  /// A request through Claude's hooks (a session outside Mikky).
  final ({String? description, String request})? hook;

  /// Stopped by its limit, and « Terminée » by the user.
  final bool limitFinished;

  /// A message can be sent (the engine is there).
  final bool canSend;
}

/// What the user does on an agent's page.
class AgentPageActions {
  const AgentPageActions({
    required this.back,
    this.send,
    this.answer,
    this.answerQuestion,
    this.resume,
    this.finishLimit,
    this.unfinishLimit,
    this.menu,
  });

  final VoidCallback back;
  final Future<void> Function(String text)? send;
  final ValueChanged<AgentAnswer>? answer;
  final ValueChanged<Map<String, Object>?>? answerQuestion;
  final VoidCallback? resume, finishLimit, unfinishLimit, menu;
}

/// An agent's page (UX `ux-a.html`): one thread, the conversation with
/// the work where it happened — each task unfolds what the agent did and
/// said, in order, live while it works (user request, 2026-10-05: no more
/// Suivi and Chat apart). The conversation goes on under it. Sessions
/// started elsewhere are followed without touching them; once done they
/// can go on in Mikky.
class AgentPageView extends StatefulWidget {
  const AgentPageView({super.key, required this.model, required this.actions, this.scrolledTo, this.mikky, this.drawMikky = true});

  final AgentPageModel model;
  final AgentPageActions actions;

  /// Mikky on the left, the thread on the right (the notch, « au milieu »,
  /// 2026-10-05). Null: the centered reading column (the right edge).
  final MikkyBeside? mikky;

  /// False: the island draws its own Mikky in his place (the app).
  final bool drawMikky;

  /// Opens scrolled this far from the top (the boards), instead of at the
  /// end of the conversation.
  final double? scrolledTo;

  @override
  State<AgentPageView> createState() => _AgentPageViewState();
}

class _AgentPageViewState extends State<AgentPageView> {
  late final _scroll = ScrollController(initialScrollOffset: widget.scrolledTo ?? 0);
  late int _lastVersion = widget.scrolledTo == null ? -1 : widget.model.log.version;
  String? _sendError;

  /// The finished turns' widgets, kept between builds.
  final _thread = ThreadCache();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    try {
      await widget.actions.send!(text);
      if (mounted) setState(() => _sendError = null);
    } catch (e) {
      if (mounted) setState(() => _sendError = 'Envoi non confirmé : $e');
    }
  }

  /// Stays at the bottom as the conversation grows (unless the user
  /// scrolled up to read).
  void _follow(SessionLog log) {
    if (log.version == _lastVersion) return;
    // Opening the page: straight to the end of the conversation.
    final first = _lastVersion == -1;
    _lastVersion = log.version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final p = _scroll.position;
      if (first || p.maxScrollExtent - p.pixels < 160) _toEnd();
    });
  }

  /// To the end of the thread. The list builds lazily: its length is
  /// known for sure once the end is laid out, so it checks again over the
  /// next frames.
  void _toEnd([int tries = 4]) {
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent) return;
    _scroll.jumpTo(p.maxScrollExtent);
    if (tries > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _toEnd(tries - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final m = widget.model;
    final a = widget.actions;
    final log = m.log;
    final working = log.working;
    _follow(log);

    final usage = usageLine(log);
    final hook = m.hook;
    final content = <Widget>[
      if (_sendError != null) Text(_sendError!, style: uiText(12, color: ui.red)),
      if (m.adapterPid != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('Adaptateur ACP · PID ${m.adapterPid} · ${m.host == AgentHost.wsl ? 'WSL' : 'Windows'}', style: uiText(11.5, color: ui.text3, tabular: true)),
        ),
      if (usage.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(usage, style: uiText(11.5, color: ui.text3, tabular: true)),
        ),
      ...threadOf(context, log, cache: _thread, limit: LimitHooks(
        m.id,
        a.send ?? (_) async {},
        finish: a.finishLimit,
        finished: m.limitFinished,
        unfinish: a.unfinishLimit,
      )),
      if (m.status == AgentStatus.paused)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: PausedCard(onResume: a.resume ?? () {}),
        )
      else if (hook != null)
        // A session outside Mikky, asking through Claude's hooks.
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AgentCard(
            status: UiStatus.approval,
            title: 'Attend ton feu vert',
            who: '',
            subtitle: hook.description,
            style: AgentCardStyle.waiting,
            actions: WaitActions(
              command: hook.request,
              onYes: () => a.answer?.call(AgentAnswer.allow),
              onNo: () => a.answer?.call(AgentAnswer.deny),
            ),
          ),
        )
      else if ((log.pending.isNotEmpty || log.question != null) && m.live)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: log.question != null
              ? QuestionCard(question: log.question!, onAnswer: (answers) => a.answerQuestion?.call(answers))
              : AskCard(log: log, onAnswer: (answer) => a.answer?.call(answer)),
        ),
    ];

    final Widget? composer = m.external && working
        ? null
        : Composer(
            key: ValueKey('composer:${m.id}'),
            placeholder: working
                ? 'Écris à cet agent…'
                : m.external
                ? 'Continuer dans Mikky…'
                : 'Continuer avec cet agent…',
            commands: m.live ? log.commands : const [],
            onSend: m.canSend && a.send != null ? _send : null,
            glass: true,
          );

    return ThreadPage(
      scroll: _scroll,
      back: a.back,
      // No pause button any more: « Mettre en pause », « Reprendre » and
      // « Arrêter l'agent » are in the ··· menu (user request, 2026-09-30).
      menu: a.menu ?? () {},
      // The violet star under the spell (« Ensorcelé »), the yellow one
      // while the limit holds it (user requests, 2026-09-30).
      overlay: SpellStar(id: m.id, limited: m.status == AgentStatus.rateLimited),
      mikky: widget.mikky,
      drawMikky: widget.drawMikky,
      mikkyState: mikkyStateOf(m.status),
      empty: Text('Rien à montrer', style: uiText(13, color: ui.text3)),
      composer: composer,
      note: Row(children: [
        MikkyIcon('lock', size: 13, color: ui.text3),
        const SizedBox(width: 6),
        Expanded(child: Text('Session extérieure : activité observée, processus non vérifié.', style: uiText(11.5, color: ui.text3, height: 1.35))),
      ]),
      children: content,
    );
  }
}
