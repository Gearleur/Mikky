import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../agents/agents_service.dart';
import '../overlay/overlay_channel.dart';
import '../side/side_app.dart';
import '../ui/buttons.dart';
import '../ui/tokens.dart';

/// A normal desktop window sharing the island's backend and session widgets.
class HomeApp extends StatefulWidget {
  const HomeApp({super.key, required this.service, required this.overlay});
  final AgentsService service;
  final OverlayChannel overlay;
  @override
  State<HomeApp> createState() => _HomeAppState();
}

class _HomeAppState extends State<HomeApp> {
  String? _error;
  Future<void> _settings() async {
    final service = widget.service;
    final choice = await widget.overlay.showMenu([
      MenuEntry(1, 'Moteur au démarrage de Windows', checked: service.autostartEnabled),
      const MenuEntry(2, 'Arrêter tous les agents…'),
    ]);
    try {
      if (choice == 1) await service.setAutostart(!service.autostartEnabled);
      if (choice == 2) {
        final confirm = await widget.overlay.showMenu([
          const MenuEntry(1, 'Confirmer l’arrêt de tous les agents'),
          const MenuEntry(2, 'Annuler'),
        ]);
        if (confirm == 1) await service.stopAll();
      }
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = 'Action non confirmée : $e');
    }
  }

  @override
  void dispose() {
    unawaited(widget.service.shutdown());
    widget.service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WidgetsApp(
    title: 'Mikky · Espace de travail',
    color: MikkyUi.light.board,
    debugShowCheckedModeBanner: false,
    builder: (context, _) => MikkyUiTheme(
      ui: MediaQuery.platformBrightnessOf(context) == Brightness.dark ? MikkyUi.dark : MikkyUi.light,
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => ListenableBuilder(
              listenable: widget.service,
              builder: (context, _) {
                final service = widget.service;
                final host = SideHost(
                  service: service,
                  answer: (id, answer) => service.source.answer(id, answer, service.source.clock()),
                  pickFolder: widget.overlay.pickFolder,
                  showMenu: widget.overlay.showMenu,
                  islandMenu: _settings,
                );
                String status(AgentHost host) => switch (service.target(host).state) {
                  TargetState.ready => 'Prêt',
                  TargetState.installing => 'Préparation…',
                  TargetState.checking => service.canLaunch ? 'Préparation au premier lancement' : 'Connexion…',
                  TargetState.unavailable => 'Indisponible',
                };
                return WorkspaceShell(
                  windows: status(AgentHost.windows),
                  wsl: status(AgentHost.wsl),
                  count: service.source.homeEntries.length,
                  error: _error,
                  settings: _settings,
                  boards: () => Process.start(Platform.resolvedExecutable, ['--kit'], mode: ProcessStartMode.detached),
                  child: SideApp(host: host),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// The same workspace frame appears on the design board and in the app.
class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    super.key,
    required this.windows,
    required this.wsl,
    required this.count,
    required this.child,
    this.settings,
    this.boards,
    this.error,
  });
  final String windows, wsl;
  final int count;
  final Widget child;
  final VoidCallback? settings, boards;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final navigation = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mikky',
            style: uiText(28, weight: FontWeight.w600, color: ui.text),
          ),
          const SizedBox(height: 8),
          Text('Espace de travail', style: uiText(13, color: ui.text2)),
          const SizedBox(height: 40),
          Text(
            'TES MACHINES',
            style: uiText(10, weight: FontWeight.w600, color: ui.text3),
          ),
          const SizedBox(height: 20),
          Text(
            'Ce PC · Windows',
            style: uiText(14, weight: FontWeight.w600, color: ui.text),
          ),
          const SizedBox(height: 5),
          Text(windows, style: uiText(12, color: ui.text2)),
          const SizedBox(height: 24),
          Text(
            'Ubuntu · WSL',
            style: uiText(14, weight: FontWeight.w600, color: ui.text),
          ),
          const SizedBox(height: 5),
          Text(wsl, style: uiText(12, color: ui.text2)),
          const Spacer(),
          Text('$count sessions', style: uiText(13, color: ui.text2)),
          const SizedBox(height: 16),
          MButton('Réglages du moteur', small: true, onPressed: settings),
          const SizedBox(height: 10),
          MButton('Planches & technique', small: true, onPressed: boards),
          const SizedBox(height: 24),
          Text('Fermer cette fenêtre laisse les agents continuer.', style: uiText(12, color: ui.text3, height: 1.5)),
        ],
      ),
    );
    return ColoredBox(
      color: ui.board,
      child: LayoutBuilder(
        builder: (context, size) => Row(
          children: [
            if (size.maxWidth >= 760) SizedBox(width: 250, child: navigation),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(size.maxWidth >= 760 ? 24 : 8),
                child: Column(
                  children: [
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(error!, style: uiText(13, color: ui.red)),
                      ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: ColoredBox(color: ui.island, child: child),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
