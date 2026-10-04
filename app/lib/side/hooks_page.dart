import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/buttons.dart';
import '../ui/cards.dart';
import '../ui/side.dart';
import '../ui/tokens.dart';
import 'side_app.dart';

/// The hooks of Claude Code or Codex (2026-10-04): with them, a session
/// started in a terminal or VS Code asks its permissions in Mikky too. Never written
/// without the user: the exact change to `settings.json` first, then
/// Installer (or Désinstaller); a dated copy is kept, and a file changed
/// meanwhile is refused (`daemon/mikkyd/src/claude_settings.rs`).
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
    _status = await widget.host.service.hooksStatus(widget.tool);
  });

  Future<void> _show(bool install) => _run(() async {
    _message = null;
    _installing = install;
    _preview = await widget.host.service.hooksPreview(widget.tool, install: install);
  });

  Future<void> _write() => _run(() async {
    final p = _preview!;
    final backup = await widget.host.service.hooksWrite(widget.tool, install: _installing!, fingerprint: p['fingerprint']! as String);
    _message = _installing!
        ? 'Installé. Les prochaines demandes de $_name passent aussi par Mikky.'
        : 'Désinstallé. $_name demande de nouveau seulement dans son terminal.';
    if (_installing! && widget.tool == AgentProvider.codex) {
      _message = '$_message\nDans Codex, valide-les une fois avec /hooks.';
    }
    if (backup != null) _message = '$_message\nCopie de l’ancien fichier : $backup';
    _preview = null;
    _status = await widget.host.service.hooksStatus(widget.tool);
  });

  String get _name => widget.tool == AgentProvider.codex ? 'Codex' : 'Claude';

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final status = _status;
    final installed = status?['installed'] == true;
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
                  'Avec les hooks, une session $_name lancée dans un terminal ou VS Code te demande aussi ses permissions ici. '
                  'Sans réponse dans Mikky, $_name demande dans son terminal, comme avant.',
                  style: text,
                ),
                const SizedBox(height: 10),
                if (status != null)
                  Text(
                    installed ? 'Installés dans ${status['settingsPath']}' : 'Pas installés.',
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
                    child: AnswerBar(answers: [
                      if (installed) ('Désinstaller…', _busy ? null : () => _show(false)),
                      (installed ? 'Réinstaller…' : 'Installer…', _busy ? null : () => _show(true)),
                    ]),
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
                    child: AnswerBar(answers: [
                      ('Annuler', _busy ? null : () => setState(() => _preview = null)),
                      if (preview['changes'] == true)
                        (_installing! ? 'Installer' : 'Désinstaller', _busy ? null : _write),
                    ]),
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
