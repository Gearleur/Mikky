import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/agents_service.dart';
import '../theme.dart';
import '../ui/foundation/surface.dart';
import '../ui/foundation/tokens.dart';
import '../ui/overlays/sheet.dart';
import 'settings_controller.dart';
import 'settings_top_view.dart';
import 'settings_view.dart';

/// Live settings over the current screen, without discarding its drafts.
Future<void> showSettingsSheet(
  BuildContext within, {
  required SettingsController controller,
  required AgentsService service,
  required bool top,
  required ValueChanged<AgentProvider> openHooks,
  required VoidCallback diagnostics,
}) => showSheetPage(
  within,
  themeUpdates: controller,
  resolveTheme: (context) => MikkyTheme.resolve(controller.settings.theme, MediaQuery.platformBrightnessOf(context)).ui,
  builder: (_) =>
      SettingsSheet(controller: controller, service: service, top: top, openHooks: openHooks, diagnostics: diagnostics),
);

/// Owns only reads and UI request state. Preference effects and saving live
/// in the controller; hooks retain their explicit preview before writing.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.controller,
    required this.service,
    required this.top,
    required this.openHooks,
    required this.diagnostics,
  });

  final SettingsController controller;
  final AgentsService service;
  final bool top;
  final ValueChanged<AgentProvider> openHooks;
  final VoidCallback diagnostics;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final _hooks = <AgentProvider, SettingsHookState>{};
  late final _edge = widget.controller.settings.edge;
  late bool _autostart = widget.service.autostartEnabled;
  late BackendState _backend = widget.service.backend;
  bool _loading = false, _busy = false;
  String? _issue;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.service.addListener(_serviceChanged);
    unawaited(_loadHooks());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.service.removeListener(_serviceChanged);
    super.dispose();
  }

  void _changed() {
    if (widget.controller.settings.edge != _edge) {
      unawaited(Sheet.dismiss(context, animated: false));
    } else if (mounted) {
      setState(() {});
    }
  }

  void _serviceChanged() {
    if (_backend == widget.service.backend && _autostart == widget.service.autostartEnabled) return;
    if (!mounted) return;
    setState(() {
      _backend = widget.service.backend;
      _autostart = widget.service.autostartEnabled;
    });
    if (_backend == BackendState.online) unawaited(_loadHooks());
  }

  Future<void> _loadHooks() async {
    if (_loading || widget.service.backend != BackendState.online) return;
    _loading = true;
    await Future.wait([
      for (final provider in AgentProvider.values)
        () async {
          var state = SettingsHookState.unknown;
          try {
            final status = await widget.service.hooksStatus(provider);
            state = status['installed'] != true
                ? SettingsHookState.missing
                : status['upToDate'] == false
                ? SettingsHookState.outdated
                : SettingsHookState.active;
          } catch (_) {
            /* Remains unverified; opening Hooks offers details. */
          }
          if (mounted) setState(() => _hooks[provider] = state);
        }(),
    ]);
    _loading = false;
  }

  Future<void> _setAutostart(bool value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _issue = null;
    });
    try {
      await widget.service.setAutostart(value);
    } catch (_) {
      _issue = 'Démarrage non modifié';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _autostart = widget.service.autostartEnabled;
      });
    }
  }

  Future<void> _leave(VoidCallback next) async {
    await Sheet.dismiss(context);
    next();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ui = MikkyTheme.resolve(c.settings.theme, MediaQuery.platformBrightnessOf(context)).ui;
    final error = _issue ?? c.error;
    final actions = SettingsPageActions(
      back: () => unawaited(Sheet.dismiss(context)),
      change: (update) => unawaited(c.change(update)),
      setAutostart: _backend == BackendState.online && !_busy ? (value) => unawaited(_setAutostart(value)) : null,
      hooks: (provider) => unawaited(_leave(() => widget.openHooks(provider))),
      diagnostics: () => unawaited(_leave(widget.diagnostics)),
      retrySave: _issue == null && c.applyError == null && c.saveFailed ? () => unawaited(c.flush()) : null,
    );
    return MikkyUiScope(
      ui: ui,
      child: widget.top
          ? Align(
              child: SizedBox(
                height: 200,
                child: SettingsTopView(
                  settings: c.settings,
                  actions: actions,
                  autostart: _autostart,
                  claude: _hooks[AgentProvider.claude] ?? SettingsHookState.unknown,
                  codex: _hooks[AgentProvider.codex] ?? SettingsHookState.unknown,
                  saveError: error != null,
                  errorMessage: error,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Surface(
                color: ui.island,
                radius: Radii.xl,
                shadows: ui.floating,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.xl),
                  child: SettingsPageView(
                    settings: c.settings,
                    actions: actions,
                    autostart: _autostart,
                    version: '0.1.0',
                    claude: _hooks[AgentProvider.claude] ?? SettingsHookState.unknown,
                    codex: _hooks[AgentProvider.codex] ?? SettingsHookState.unknown,
                    saveError: error != null,
                    errorMessage: error,
                  ),
                ),
              ),
            ),
    );
  }
}
