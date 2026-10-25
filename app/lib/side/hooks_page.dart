import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/content/cards.dart';
import '../ui/content/side.dart';
import '../ui/controls/buttons.dart';
import '../ui/controls/environment_selector.dart';
import '../ui/foundation/tokens.dart';
import 'side_app.dart';

/// The hooks of Claude Code or Codex (2026-10-04): with them, a session
/// started in a terminal or VS Code asks its permissions in Mikky too. Never written
/// without the user: the exact change to `settings.json` first, then
/// Installer (or Désinstaller); a dated copy is kept, and a file changed
/// meanwhile is refused (`daemon/mikkyd/src/hooks/settings.rs`).
///
/// FUNCTIONAL ONLY: no design of its own yet (plan of 2026-10-05).
class HooksPage extends StatefulWidget {
  const HooksPage({super.key, required this.host, required this.back, this.tool = AgentProvider.claude});

  final SideHost host;
  final AgentProvider tool;
  final VoidCallback back;

  @override
  State<HooksPage> createState() => _HooksPageState();
}

class _HooksPageState extends State<HooksPage> {
  Map<String, Object?>? _status;
  Map<String, Object?>? _preview;
  bool? _installing;
  String? _message;
  bool _busy = false;

  /// Windows, or WSL (its hooks call the Windows relay).
  AgentHost _host = AgentHost.windows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _run(Future<void> Function() step) async {
    setState(() => _busy = true);
    try {
      await step();
    } catch (e) {
      _message = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _load() => _run(() async {
    _status = await widget.host.service.hooksStatus(widget.tool, host: _host);
  });

  Future<void> _show(bool install) => _run(() async {
    _message = null;
    _installing = install;
    _preview = await widget.host.service.hooksPreview(widget.tool, install: install, host: _host);
  });

  Future<void> _write() => _run(() async {
    final p = _preview!;
    final backup = await widget.host.service.hooksWrite(
      widget.tool,
      install: _installing!,
      fingerprint: p['fingerprint']! as String,
      host: _host,
    );
    _message = _installing!
        ? 'Installé. Les prochaines demandes de $_name passent aussi par Mikky.'
        : 'Désinstallé. $_name demande de nouveau seulement dans son terminal.';
    if (_installing! && widget.tool == AgentProvider.codex) {
      _message = '$_message\nDans Codex, valide-les une fois avec /hooks.';
    }
    if (backup != null) _message = '$_message\nCopie de l’ancien fichier : $backup';
    _preview = null;
    _status = await widget.host.service.hooksStatus(widget.tool, host: _host);
  });

  String get _name =>
      '${widget.tool == AgentProvider.codex ? 'Codex' : 'Claude'}${_host == AgentHost.wsl ? ' dans WSL' : ''}';

  void _pick(MikkyEnvironment environment) {
    final host = switch (environment) {
      MikkyEnvironment.local => AgentHost.windows,
      MikkyEnvironment.wsl => AgentHost.wsl,
      _ => null,
    };
    if (host == null || host == _host) return;
    setState(() {
      _host = host;
      _status = null;
      _preview = null;
      _message = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final status = _status;
    final installed = status?['installed'] == true;
    // Installed by an older Mikky: some events are missing or changed.
    final stale = installed && status?['upToDate'] == false;
    final preview = _preview;
    final text = uiText(TextSize.small, color: ui.text2, height: 1.4);
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 68, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Avec les hooks, une session $_name lancée ailleurs (terminal, VS Code, app Claude) montre aussi ses permissions et ses questions ici. '
                  'Tu réponds dans Mikky ou là-bas : la première réponse gagne, rien n’attend.',
                  style: text,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: EnvironmentSelector(
                    selected: _host == AgentHost.wsl ? MikkyEnvironment.wsl : MikkyEnvironment.local,
                    onChanged: _pick,
                    menuWithin: context,
                    small: true,
                  ),
                ),
                const SizedBox(height: 10),
                if (status != null)
                  Text(
                    !installed
                        ? 'Pas installés.'
                        : stale
                        ? 'Installés dans ${status['settingsPath']}, mais d’une ancienne version de Mikky : à mettre à jour.'
                        : 'Installés et à jour dans ${status['settingsPath']}.',
                    style: uiText(TextSize.caption, color: ui.text3),
                  ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(_message!, style: uiText(TextSize.caption, color: ui.text)),
                ],
                const SizedBox(height: 12),
                if (preview == null && status != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: AnswerBar(
                      answers: [
                        if (installed) ('Désinstaller…', _busy ? null : () => _show(false)),
                        (
                          !installed
                              ? 'Installer…'
                              : stale
                              ? 'Mettre à jour…'
                              : 'Réinstaller…',
                          _busy ? null : () => _show(true),
                        ),
                      ],
                    ),
                  ),
                if (preview != null) ...[
                  Text(
                    preview['changes'] == true
                        ? 'Ce qui change dans ${preview['settingsPath']} (une copie datée sera gardée) :'
                        : 'Rien ne change dans ${preview['settingsPath']}.',
                    style: text,
                  ),
                  const SizedBox(height: 8),
                  if (preview['changes'] == true) CodePill('${preview['diff']}', maxLines: 40),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AnswerBar(
                      answers: [
                        ('Annuler', _busy ? null : () => setState(() => _preview = null)),
                        if (preview['changes'] == true)
                          (_installing! ? 'Installer' : 'Désinstaller', _busy ? null : _write),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SideHead(
          title: widget.tool == AgentProvider.codex ? 'Hooks Codex' : 'Hooks Claude Code',
          small: true,
          leading: RoundButton('left', size: 34, onPressed: widget.back, tooltip: 'Retour'),
        ),
      ],
    );
  }
}
