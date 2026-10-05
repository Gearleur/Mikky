import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mikky_agents/mikky_agents.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/agents_service.dart';
import '../home/new_task.dart';
import '../overlay/overlay_channel.dart';
import '../ui/brand_logo.dart';
import '../ui/buttons.dart';
import '../ui/cards.dart';
import '../ui/feedback.dart';
import '../ui/field.dart';
import '../ui/side.dart';
import '../ui/tokens.dart';
import '../ui/thread_page.dart';
import 'session_text.dart';
import 'side_app.dart';

/// A new chat (2026-10-05: « comme pour l'agent, un chat vide »): a page
/// as an agent's ([NewChatView]), the field with the folder and the model
/// half inside. The model's menu also holds where it runs (Windows / WSL,
/// from the folder) and the permissions (Demander by default, or Auto).
class NewAgentPage extends StatefulWidget {
  const NewAgentPage({super.key, required this.host, required this.back, required this.launched, required this.login, this.mikky});

  final SideHost host;
  final VoidCallback back;

  /// In the notch, where Mikky stands (the island draws him).
  final MikkyBeside? mikky;

  /// The agent started: its page opens.
  final ValueChanged<String> launched;

  /// The sign-in to [provider] on [target], as a page of its own; [done]
  /// once signed in.
  final void Function(AgentHost target, AgentProvider provider, VoidCallback done) login;

  @override
  State<NewAgentPage> createState() => _NewAgentPageState();
}

class _NewAgentPageState extends State<NewAgentPage> {
  String? _folder;
  AgentProvider _provider = AgentProvider.claude;
  AgentHost _host = AgentHost.windows;
  PermissionMode _permissions = PermissionMode.ask;
  String? _model;
  bool _hostChosen = false;

  /// Waiting for a sign-in before launching this prompt.
  String? _error;
  bool _starting = false;

  AgentsService get _service => widget.host.service;

  @override
  void initState() {
    super.initState();
    final recent = _service.store.recentFolders;
    if (recent.isNotEmpty) _useFolder(recent.first);
  }

  void _useFolder(String folder) {
    _folder = folder;
    final choice = _service.store.choices[folder];
    if (choice != null) {
      _provider = choice.provider;
      _host = choice.host;
      _permissions = choice.permissions;
      _model = choice.model;
      _hostChosen = true;
    } else {
      _host = hostOfFolder(folder);
      _hostChosen = false;
    }
  }

  // ------------------------------------------------------------- menus

  static const _browse = 1, _recent = 100;

  Future<void> _folderMenu() async {
    final recent = _service.store.recentFolders;
    final chosen = recent.isEmpty
        ? _browse
        : await widget.host.showMenu([
            for (var i = 0; i < recent.length; i++) MenuEntry(_recent + i, recent[i], checked: recent[i] == _folder),
            const MenuEntry.separator(),
            const MenuEntry(_browse, 'Parcourir…'),
          ]);
    if (chosen == null) return;
    if (chosen == _browse) {
      await _pickFolder();
    } else {
      setState(() => _useFolder(recent[chosen - _recent]));
    }
  }

  Future<bool> _pickFolder() async {
    final folder = await widget.host.pickFolder('Dossier de l’agent');
    if (folder == null) return false;
    setState(() => _useFolder(folder));
    return true;
  }

  static const _claude = 1, _codex = 2, _windows = 3, _wsl = 4, _ask = 5, _auto = 6, _defaultModel = 7, _models = 100;

  Future<void> _modelMenu() async {
    final models = offeredModels(_service.models[_provider] ?? const []);
    final wsl = _service.target(AgentHost.wsl);
    final chosen = await widget.host.showMenu([
      MenuEntry(_claude, 'Claude', checked: _provider == AgentProvider.claude),
      MenuEntry(_codex, 'Codex', checked: _provider == AgentProvider.codex),
      const MenuEntry.separator(),
      MenuEntry(_defaultModel, 'Modèle par défaut', checked: _model == null),
      for (var i = 0; i < models.length; i++) MenuEntry(_models + i, models[i].name, checked: models[i].id == _model),
      const MenuEntry.separator(),
      MenuEntry(_windows, 'Où : Windows', checked: _host == AgentHost.windows),
      MenuEntry(_wsl, wsl.state == TargetState.unavailable ? 'Où : WSL (indisponible)' : 'Où : WSL', checked: _host == AgentHost.wsl),
      const MenuEntry.separator(),
      MenuEntry(_ask, 'Permissions : demander', checked: _permissions == PermissionMode.ask),
      MenuEntry(_auto, 'Permissions : auto', checked: _permissions == PermissionMode.auto),
    ]);
    if (chosen == null) return;
    setState(() {
      switch (chosen) {
        case _claude || _codex:
          final p = chosen == _claude ? AgentProvider.claude : AgentProvider.codex;
          if (p != _provider) _model = null;
          _provider = p;
        case _windows:
          _host = AgentHost.windows;
          _hostChosen = true;
        case _wsl:
          if (wsl.state != TargetState.unavailable) {
            _host = AgentHost.wsl;
            _hostChosen = true;
          }
        case _ask:
          _permissions = PermissionMode.ask;
        case _auto:
          _permissions = PermissionMode.auto;
        case _defaultModel:
          _model = null;
        default:
          if (chosen >= _models) _model = models[chosen - _models].id;
      }
    });
  }

  String get _modelLabel {
    final name = _provider == AgentProvider.claude ? 'Claude' : 'Codex';
    final m = _model;
    if (m == null) return name;
    final known = (_service.models[_provider] ?? const <SessionModel>[]).where((x) => x.id == m).firstOrNull;
    return known?.name ?? m;
  }

  // ------------------------------------------------------------ launch

  Future<void> _send(String text) async {
    if (_starting) return;
    if (_folder == null && !await _pickFolder()) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final host = _hostChosen ? _host : hostOfFolder(_folder!);
      final auth = _service.auth[(host, _provider)] ?? await _service.checkAuth(host, _provider);
      if (!auth.installed || !auth.loggedIn) {
        setState(() => _starting = false);
        widget.login(host, _provider, () => _send(text));
        return;
      }
      final id = await _service.launch(LaunchRequest(
        provider: _provider,
        host: host,
        cwd: _folder!,
        prompt: text,
        permissions: _permissions,
        model: _model,
      ));
      widget.launched(id);
      // In the home, the Chat stays: ready for the next one.
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      setState(() {
        _error = '$e';
        _starting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final installing = _service.target(_hostChosen ? _host : hostOfFolder(_folder ?? '')).state == TargetState.installing;
    final composer = Composer(
      placeholder: 'Que doit faire l’agent ?',
      autofocus: true,
      onSend: _send,
      options: Row(mainAxisSize: MainAxisSize.min, children: [
        ComposerChip(_folder == null ? 'Dossier' : folderName(_folder), icon: 'folder', onTap: _folderMenu),
        const SizedBox(width: 6),
        ComposerChip(_modelLabel, leading: BrandLogo(Brand.of(_provider), size: 12), onTap: _modelMenu),
      ]),
    );
    return NewChatView(
      back: widget.back,
      mikky: widget.mikky,
      drawMikky: false,
      composer: composer,
      status: installing ? 'Mikky installe ses adaptateurs…' : (_starting ? 'Démarrage…' : null),
      error: _error,
    );
  }
}

/// Sign-in, as Paperclip does it: Mikky runs the tool's own login and shows
/// its link (and Codex's one-time code); the tool keeps the credential.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.host, required this.target, required this.provider, required this.back, required this.done});

  final SideHost host;
  final AgentHost target;
  final AgentProvider provider;
  final VoidCallback back;
  final VoidCallback done;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  Login? _login;
  LoginPrompt? _prompt;
  String? _failed;
  bool _checking = false;
  StreamSubscription<LoginState>? _sub;

  String get _tool => widget.provider == AgentProvider.claude ? 'Claude' : 'Codex';
  String get _where => widget.target == AgentHost.wsl ? 'dans WSL' : 'sous Windows';

  @override
  void dispose() {
    _sub?.cancel();
    _login?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _failed = null;
      _prompt = null;
    });
    final login = await widget.host.service.login(widget.target, widget.provider);
    if (login == null) {
      setState(() => _failed = 'Mikky ne trouve pas $_tool $_where.');
      return;
    }
    _login = login;
    _sub = login.states.listen((s) async {
      switch (s) {
        case LoginPrompt():
          setState(() => _prompt = s);
          _openLink(s.url);
        case LoginDone(ok: true):
          setState(() => _checking = true);
          final auth = await widget.host.service.checkAuth(widget.target, widget.provider);
          if (!mounted) return;
          if (auth.loggedIn) {
            widget.done();
          } else {
            setState(() {
              _checking = false;
              _failed = 'La connexion n’a pas abouti.';
            });
          }
        case LoginDone():
          setState(() => _failed = s.message == null ? 'La connexion n’a pas abouti.' : 'La connexion n’a pas abouti : ${s.message}');
      }
    });
  }

  void _openLink(String url) => Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final prompt = _prompt;
    final installed = widget.host.service.auth[(widget.target, widget.provider)]?.installed ?? true;
    return Stack(children: [
      SideHead(title: 'Connexion à $_tool', small: true, leading: RoundButton('left', size: 34, onPressed: widget.back, tooltip: 'Retour')),
      Positioned.fill(
        top: 68,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              installed ? '$_tool n’est pas connecté $_where.' : '$_tool n’est pas installé $_where.',
              style: uiText(TextSize.lead, weight: FontWeight.w600, color: ui.text),
            ),
            const SizedBox(height: 6),
            Text(
              installed
                  ? 'Mikky lance la connexion officielle de $_tool. Tu te connectes dans ton navigateur ; Mikky ne voit jamais ton mot de passe ni tes jetons.'
                  : widget.provider == AgentProvider.claude
                      ? 'Installe Claude Code (claude.ai/install), puis reviens ici.'
                      : 'Installe Codex (npm install -g @openai/codex), puis reviens ici.',
              style: uiText(TextSize.label, color: ui.text2),
            ),
            const SizedBox(height: 20),
            if (prompt?.code != null) ...[
              Text('Ton code, à taper sur la page qui s’ouvre :', style: uiText(TextSize.small, color: ui.text2)),
              const SizedBox(height: 8),
              Center(child: Text(prompt!.code!, style: uiText(TextSize.display, weight: FontWeight.w600, mono: true, color: ui.text, tracking: .06))),
              const SizedBox(height: 12),
            ],
            if (prompt != null) ...[
              Row(children: [
                const Spinner(size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(_checking ? 'Vérification…' : 'En attente de ta connexion…', style: uiText(TextSize.small, color: ui.text2))),
                MButton('Ouvrir le lien', small: true, onPressed: () => _openLink(prompt.url)),
              ]),
            ] else if (installed)
              MButton('Se connecter', kind: ButtonKind.primary, onPressed: _start)
            else
              MButton('J’ai installé $_tool', kind: ButtonKind.primary, onPressed: () async {
                final auth = await widget.host.service.checkAuth(widget.target, widget.provider);
                if (auth.loggedIn) {
                  widget.done();
                } else {
                  setState(() {});
                }
              }),
            if (_failed != null) ...[
              const SizedBox(height: 14),
              Text(_failed!, style: uiText(TextSize.small, color: ui.red)),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: MButton('Réessayer', small: true, onPressed: _start)),
            ],
            const Spacer(),
            if (prompt != null) CodePill(prompt.url),
          ]),
        ),
      ),
    ]);
  }
}
