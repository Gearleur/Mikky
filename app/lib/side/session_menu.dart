import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../overlay/overlay_channel.dart';
import '../ui/buttons.dart';
import '../ui/field.dart';
import '../ui/side.dart';
import '../ui/tokens.dart';
import 'side_app.dart';

const _rename = 1, _pin = 2, _archive = 3, _settle = 4, _delete = 5, _code = 6, _folder = 7;
const _forget = 10, _forgetAndFile = 11, _cancel = 12;

/// What to do with a session (a right click on its card, or ⋯ on its
/// page): rename, pin, archive, settle an error, delete. Deleting asks
/// again, and deletes Claude's or Codex's own file only if asked.
Future<void> showSessionMenu(SideHost host, AgentEntry e, {required VoidCallback rename, VoidCallback? deleted}) async {
  final source = host.service.source;
  final m = e.mark;
  final busy = e.live && e.log.working;
  final folder = e.cwd ?? e.log.cwd;
  final chosen = await host.showMenu([
    if (folder != null) ...[
      const MenuEntry(_code, 'Ouvrir dans VS Code'),
      const MenuEntry(_folder, 'Ouvrir le dossier'),
      const MenuEntry.separator(),
    ],
    const MenuEntry(_rename, 'Renommer…'),
    MenuEntry(_pin, m.pinned ? 'Désépingler' : 'Épingler'),
    MenuEntry(_archive, m.archived ? 'Sortir des archives' : 'Archiver'),
    if (e.homeStatus == AgentStatus.error) const MenuEntry(_settle, 'Marquer l’erreur comme réglée'),
    if (!busy) ...[const MenuEntry.separator(), const MenuEntry(_delete, 'Supprimer…')],
  ]);
  switch (chosen) {
    case _code:
      openInVsCode(folder!, e.host);
    case _folder:
      openFolder(folder!, e.host);
    case _rename:
      rename();
    case _pin:
      source.setPinned(e.id, !m.pinned);
    case _archive:
      source.setArchived(e.id, !m.archived);
    case _settle:
      source.settle(e.id);
    case _delete:
      final how = await host.showMenu([
        const MenuEntry(_forget, 'Supprimer de Mikky (le fichier de session reste)'),
        if (e.watched != null) MenuEntry(_forgetAndFile, 'Supprimer aussi le fichier de ${e.provider == AgentProvider.claude ? 'Claude' : 'Codex'} (définitif)'),
        const MenuEntry.separator(),
        const MenuEntry(_cancel, 'Annuler'),
      ]);
      if (how == _forget || how == _forgetAndFile) {
        await source.forget(e.id, deleteFile: how == _forgetAndFile);
        deleted?.call();
      }
  }
}

/// The folder in the Windows file explorer (a WSL folder through
/// `\\wsl.localhost`).
void openFolder(String folder, AgentHost host) {
  final path = host == AgentHost.wsl ? WslTarget().windowsPath(folder) : folder;
  Process.run('explorer.exe', [path]);
}

/// The folder in VS Code; in WSL, through VS Code's WSL extension.
void openInVsCode(String folder, AgentHost host) {
  if (host == AgentHost.wsl) {
    final linux = WslTarget().linuxPath(folder);
    Process.run('cmd', ['/c', 'code', '--folder-uri', 'vscode-remote://wsl+Ubuntu$linux']);
  } else {
    Process.run('cmd', ['/c', 'code', folder]);
  }
}

/// Gives a session its own name (empty: back to the agent's title).
class RenamePage extends StatefulWidget {
  const RenamePage({super.key, required this.host, required this.id, required this.back});

  final SideHost host;
  final String id;
  final VoidCallback back;

  @override
  State<RenamePage> createState() => _RenamePageState();
}

class _RenamePageState extends State<RenamePage> {
  late final _name = TextEditingController(text: widget.host.service.source.entry(widget.id)?.name ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save(String name) {
    widget.host.service.source.rename(widget.id, name);
    widget.back();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Stack(children: [
      SideHead(title: 'Renommer', small: true, leading: RoundButton('left', size: 34, onPressed: widget.back, tooltip: 'Retour')),
      Positioned(
        left: 20,
        right: 20,
        top: 96,
        child: Text('Un nom à toi pour cette session. Vide : le titre donné par l’agent.', style: uiText(13, color: ui.text2)),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 14,
        child: Composer(controller: _name, placeholder: 'Nom de la session', autofocus: true, onSend: _save, onEmptySend: () => _save('')),
      ),
    ]);
  }
}
