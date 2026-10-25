import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../settings.dart';
import '../theme.dart';
import '../ui/brand/brand_logo.dart';
import '../ui/content/side.dart';
import '../ui/foundation/icons.dart';
import '../ui/foundation/surface.dart';
import '../ui/foundation/tokens.dart';
import 'settings_controls.dart';

typedef ChangeSettings = void Function(void Function(Settings) update);

enum SettingsHookState {
  active('Hooks activés'),
  missing('Hooks à configurer'),
  outdated('Hooks à mettre à jour'),
  unknown('État non vérifié');

  const SettingsHookState(this.label);
  final String label;
}

class SettingsPageActions {
  const SettingsPageActions({
    required this.back,
    required this.change,
    required this.setAutostart,
    required this.hooks,
    required this.diagnostics,
    this.retrySave,
  });

  final VoidCallback back, diagnostics;
  final VoidCallback? retrySave;
  final ChangeSettings change;
  final ValueChanged<bool>? setAutostart;
  final ValueChanged<AgentProvider> hooks;
}

/// The shared settings screen. Its caller owns state and persistence;
/// design boards never touch the user's configuration or daemon.
class SettingsPageView extends StatefulWidget {
  const SettingsPageView({
    super.key,
    required this.settings,
    required this.actions,
    required this.autostart,
    required this.version,
    this.claude = SettingsHookState.unknown,
    this.codex = SettingsHookState.unknown,
    this.saveError = false,
    this.errorMessage,
    this.initialScroll = 0,
  });

  final Settings settings;
  final SettingsPageActions actions;
  final bool autostart, saveError;
  final String? errorMessage;
  final String version;
  final SettingsHookState claude, codex;
  final double initialScroll;

  @override
  State<SettingsPageView> createState() => _SettingsPageViewState();
}

class _SettingsPageViewState extends State<SettingsPageView> {
  late final _scroll = ScrollController(initialScrollOffset: widget.initialScroll);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final a = widget.actions;
    final ui = MikkyUi.of(context);
    return Column(
      children: [
        SideHead(
          title: 'Paramètres',
          small: true,
          leading: SettingActivator(
            label: 'Retour',
            onPressed: a.back,
            child: GestureDetector(
              onTap: a.back,
              behavior: HitTestBehavior.opaque,
              child: SizedBox.square(
                dimension: 34,
                child: Center(child: MikkyIcon('left', color: ui.text)),
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: ReadingColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.saveError) ...[
                    _SaveError(retry: a.retrySave, message: widget.errorMessage),
                    const SizedBox(height: 20),
                  ],
                  _SettingsGroup(
                    title: 'Apparence',
                    first: true,
                    children: [
                      SettingChoice(
                        'Thème',
                        options: const ['Auto', 'Clair', 'Sombre'],
                        selected: [ThemeChoice.auto, ThemeChoice.light, ThemeChoice.dark].indexOf(s.theme),
                        onChanged: (i) =>
                            a.change((s) => s.theme = [ThemeChoice.auto, ThemeChoice.light, ThemeChoice.dark][i]),
                      ),
                      SettingChoice(
                        'Position de l’île',
                        options: const ['En haut', 'À droite'],
                        selected: s.edge == IslandEdge.top ? 0 : 1,
                        onChanged: (i) => a.change((s) => s.edge = i == 0 ? IslandEdge.top : IslandEdge.right),
                      ),
                    ],
                  ),
                  _SettingsGroup(
                    title: 'Sons et notifications',
                    children: [
                      SettingToggle('Sons de Mikky', value: s.sound, onChanged: (v) => a.change((s) => s.sound = v)),
                      SettingVolume(value: s.volume, onChanged: s.sound ? (v) => a.change((s) => s.volume = v) : null),
                      SettingToggle(
                        'Notifications',
                        value: s.notifications,
                        onChanged: (v) => a.change((s) => s.notifications = v),
                      ),
                    ],
                  ),
                  _SettingsGroup(
                    title: 'Agents',
                    children: [
                      for (final (provider, state) in [
                        (AgentProvider.claude, widget.claude),
                        (AgentProvider.codex, widget.codex),
                      ])
                        SettingAction(
                          provider == AgentProvider.claude ? 'Claude Code' : 'Codex',
                          detail: state.label,
                          leading: BrandLogo(Brand.of(provider), size: 22),
                          onPressed: () => a.hooks(provider),
                        ),
                      SettingToggle(
                        'Relance après une limite',
                        value: s.autoRelaunch,
                        onChanged: (v) => a.change((s) => s.autoRelaunch = v),
                      ),
                      Text(
                        'Pour le moment, Mikky doit rester ouvert pour relancer les agents.',
                        style: uiText(TextSize.caption, color: ui.text2, height: 1.4),
                      ),
                    ],
                  ),
                  _SettingsGroup(
                    title: 'Général',
                    children: [
                      SettingToggle(
                        'Démarrage avec Windows',
                        detail: 'Le moteur suit tes agents dès la connexion.',
                        value: widget.autostart,
                        onChanged: a.setAutostart,
                      ),
                      SettingToggle(
                        'Raccourcis clavier',
                        value: s.hotkeys,
                        onChanged: (v) => a.change((s) => s.hotkeys = v),
                      ),
                      Text(
                        'Ctrl + Alt + Espace · ouvrir l’île\nCtrl + Alt + A · prochaine demande\nCtrl + Alt + M · couper les sons',
                        style: uiText(TextSize.caption, color: ui.text2, height: 1.6),
                      ),
                      const SizedBox(height: 8),
                      SettingAction('Diagnostics', onPressed: a.diagnostics),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Mikky · ${widget.version}', style: uiText(TextSize.caption, color: ui.text2)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children, this.first = false});

  final String title;
  final List<Widget> children;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first) ...[const SizedBox(height: 20), Container(height: 1, color: ui.line), const SizedBox(height: 20)],
        Text(
          title,
          style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text2),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _SaveError extends StatelessWidget {
  const _SaveError({this.retry, this.message});

  final VoidCallback? retry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Semantics(
      liveRegion: true,
      child: Surface(
        radius: Radii.lg,
        color: ui.red.withValues(alpha: .07),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message ?? 'Sauvegarde impossible',
              style: uiText(TextSize.label, color: ui.red, weight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              retry == null ? 'Le choix précédent a été conservé.' : 'Ces changements ne sont pas enregistrés.',
              style: uiText(TextSize.caption, color: ui.text2),
            ),
            if (retry != null) ...[
              const SizedBox(height: 8),
              SettingActivator(
                label: 'Réessayer la sauvegarde',
                onPressed: retry,
                child: GestureDetector(
                  onTap: retry,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Réessayer',
                      style: uiText(TextSize.label, color: ui.text, weight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
