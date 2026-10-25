import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../settings.dart';
import '../settings/quick_settings_menu.dart';
import '../settings/settings_controls.dart';
import '../settings/settings_view.dart';
import '../theme.dart';
import '../ui/content/side.dart';
import '../ui/foundation/icons.dart';
import '../ui/foundation/tokens.dart';
import 'board_settings_top.dart';
import 'canvas.dart';

final settingsBoard = BoardSpec(
  'Paramètres',
  'Une page simple et les réglages rapides au clic droit',
  (_) => [
    ...settingsTopSections(),
    const BoardSection(
      title: 'Premier essai vertical · référence',
      kind: FrameKind.trial,
      note: 'Le travail actif est le notch du haut, au début de la planche. Cette première composition verticale reste un repère pour la suite ; elle n’est pas le nouveau rendu choisi.',
      frames: [
        BoardFrame(label: 'À l’ouverture', child: SettingsTrial()),
        BoardFrame(label: 'Agents et général', child: SettingsTrial(initialScroll: 430)),
        BoardFrame(label: 'Raccourcis et diagnostics', child: SettingsTrial(initialScroll: 650)),
        BoardFrame(
          label: 'Sons coupés · hooks absents',
          child: SettingsTrial(missingHooks: true, muted: true, initialScroll: 240),
        ),
        BoardFrame(label: 'Sauvegarde impossible', child: SettingsTrial(saveError: true)),
      ],
    ),
    BoardSection(
      title: 'Clic droit — six entrées',
      kind: FrameKind.trial,
      note: 'Les réglages courants directement ; thème et position en sous-menus. Le volume et la configuration des agents restent dans la page. Flèches, Entrée, Échap ; menu d’un agent distinct.',
      frames: [
        for (final section in [null, QuickSettingsSection.theme, QuickSettingsSection.position])
          BoardFrame(
            label: switch (section) {
              null => 'Menu court',
              QuickSettingsSection.theme => 'Thème',
              QuickSettingsSection.position => 'Position',
            },
            width: section == null ? 280 : 450,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: QuickSettingsMenu(
                settings: Settings(),
                change: (_) {},
                openSettings: () {},
                closeApp: () {},
                dismiss: () {},
                initialSection: section,
              ),
            ),
          ),
      ],
    ),
    const BoardSection(
      title: 'Accès et réglages — à essayer',
      kind: FrameKind.play,
      note: 'Cliquer Paramètres, Ctrl + virgule ou clic droit dans le cadre. Page et menu partagent leur état. Retour ou Échap revient à l’accueil. Les changements restent dans cet essai, les diagnostics et les hooks sont simulés.',
      frames: [
        BoardFrame(label: 'Accueil → Paramètres · souris et clavier', child: SettingsTrial(home: true, height: 640)),
      ],
    ),
  ],
);

/// Local-only controller for the shared page and menu. No file, hook,
/// startup registration or daemon connection is used by this trial.
class SettingsTrial extends StatefulWidget {
  const SettingsTrial({
    super.key,
    this.home = false,
    this.muted = false,
    this.missingHooks = false,
    this.saveError = false,
    this.initialScroll = 0,
    this.height = 560,
  });

  final bool home, muted, missingHooks, saveError;
  final double initialScroll, height;

  @override
  State<SettingsTrial> createState() => _SettingsTrialState();
}

class _SettingsTrialState extends State<SettingsTrial> {
  late final _settings = Settings(sound: !widget.muted);
  late bool _page = !widget.home;
  late bool _error = widget.saveError;
  bool _autostart = true, _menu = false;
  String? _detail;

  void _change(void Function(Settings) update) => setState(() => update(_settings));
  void _open() => setState(() {
    _page = true;
    _menu = false;
  });
  void _back() => setState(() {
    _page = false;
    _detail = null;
  });

  @override
  Widget build(BuildContext context) {
    final ui = !widget.home
        ? MikkyUi.of(context)
        : switch (_settings.theme) {
            ThemeChoice.auto => MikkyUi.of(context),
            ThemeChoice.light => MikkyUi.light,
            ThemeChoice.dark => MikkyUi.dark,
          };
    return MikkyUiScope(
      ui: ui,
      child: Builder(builder: _frame),
    );
  }

  Widget _frame(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SideFrame(
      width: 344,
      height: widget.height,
      child: Focus(
        autofocus: widget.home,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.comma && HardwareKeyboard.instance.isControlPressed) {
            _open();
          } else if (event.logicalKey == LogicalKeyboardKey.escape && !_menu && _page) {
            _back();
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: GestureDetector(
          onSecondaryTapUp: (_) => setState(() => _menu = true),
          child: Stack(
            children: [
              if (_detail != null)
                Column(
                  children: [
                    SideHead(
                      title: _detail,
                      small: true,
                      leading: SettingActivator(
                        label: 'Retour',
                        onPressed: () => setState(() => _detail = null),
                        child: GestureDetector(
                          onTap: () => setState(() => _detail = null),
                          child: const SizedBox.square(dimension: 34, child: Center(child: MikkyIcon('left'))),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aperçu simulé sur la planche. Aucun réglage système modifié.'),
                    ),
                  ],
                )
              else if (_page)
                SettingsPageView(
                  settings: _settings,
                  autostart: _autostart,
                  version: 'aperçu',
                  claude: widget.missingHooks ? SettingsHookState.missing : SettingsHookState.active,
                  codex: widget.missingHooks ? SettingsHookState.missing : SettingsHookState.active,
                  saveError: _error,
                  initialScroll: widget.initialScroll,
                  actions: SettingsPageActions(
                    back: _back,
                    change: _change,
                    setAutostart: (v) => setState(() => _autostart = v),
                    hooks: (provider) => setState(() => _detail = 'Hooks ${provider.name}'),
                    diagnostics: () => setState(() => _detail = 'Diagnostics'),
                    retrySave: () => setState(() => _error = false),
                  ),
                )
              else
                Column(
                  children: [
                    SideHead(
                      title: 'Mikky',
                      leading: const HeadMikky(animate: false),
                      actions: [
                        SettingActivator(
                          label: 'Paramètres',
                          onPressed: _open,
                          child: GestureDetector(
                            onTap: _open,
                            child: const SizedBox.square(
                              dimension: 34,
                              child: Center(child: MikkyIcon('sliders', size: 18)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const MiniMikky(size: 76, animate: false, badge: false),
                            const SizedBox(height: 14),
                            Text(
                              'Tout est calme',
                              style: uiText(TextSize.heading, color: ui.text, weight: FontWeight.w500),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Un aperçu pour essayer les réglages.',
                              style: uiText(TextSize.small, color: ui.text2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: SettingAction('Paramètres', detail: 'Ctrl + virgule', onPressed: _open),
                    ),
                  ],
                ),
              if (_menu) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _menu = false),
                    behavior: HitTestBehavior.opaque,
                    child: ColoredBox(color: ui.island.withValues(alpha: .75)),
                  ),
                ),
                Positioned(
                  left: 18,
                  top: 86,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: QuickSettingsMenu(
                      settings: _settings,
                      change: _change,
                      openSettings: _open,
                      closeApp: () => setState(() {
                        _menu = false;
                        _detail = 'Mikky fermé · aperçu';
                      }),
                      dismiss: () => setState(() => _menu = false),
                      autofocus: true,
                      compact: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
