import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../home/home_frame.dart';
import '../home/home_layout.dart';
import '../home/home_view.dart';
import '../settings.dart';
import '../settings/settings_top_view.dart';
import '../settings/settings_view.dart';
import '../theme.dart';
import '../ui/controls/pixel_slider.dart';
import '../ui/foundation/surface.dart';
import '../ui/foundation/tokens.dart';
import '../ui/overlays/sheet.dart';
import '../ui/pixels/settings_glyph.dart';
import 'board_notch.dart' show sampleNotchApps;
import 'canvas.dart';

List<Widget> settingsTopSections() => [
  const BoardSection(
    title: 'Paramètres · notch haut',
    kind: FrameKind.trial,
    note: '700 × 200, sans agrandir l’île. Même bloc blanc et voile gris foncé translucide que l’historique (adaptés au thème sombre), quatre petites colonnes. Textes 10,5–12,5 px, pictos 20 px dans des choix de 28 px, interrupteurs 28 × 16. Taille et agencement validés ; navbar ensuite.',
    frames: [
      BoardFrame(label: 'Compact · tous les réglages', width: 700, child: SettingsTopPreview(initiallyOpen: true)),
      BoardFrame(
        label: 'Sons coupés · hooks à régler',
        width: 700,
        child: SettingsTopPreview(initiallyOpen: true, muted: true, missingHooks: true),
      ),
      BoardFrame(
        label: 'Sauvegarde impossible',
        width: 700,
        child: SettingsTopPreview(initiallyOpen: true, saveError: true),
      ),
    ],
  ),
  BoardSection(
    title: 'Les nouveaux pictos et le slider étoile',
    kind: FrameKind.trial,
    note: 'Lune violette, soleil jaune, astre jour/nuit pour suivre le système. Position : petit écran avec l’île bleue en haut ou à droite. L’étoile du volume partage son dessin et sa traînée avec la pagination ; clic, glissement, flèches, Début et Fin. Aucun mouvement au repos.',
    frames: [
      BoardFrame(label: 'Pictos · taille réelle', width: 400, child: _GlyphSamples()),
      for (final value in [0.0, .5, 1.0])
        BoardFrame(
          label: 'Volume ${(value * 100).round()} % · à essayer',
          width: 200,
          kind: FrameKind.play,
          child: PixelSliderTrial(initial: value),
        ),
    ],
  ),
  const BoardSection(
    title: 'Ouvrir les paramètres depuis le notch',
    kind: FrameKind.play,
    note: 'Bouton Paramètres en bas à gauche, Ctrl + virgule ou clic droit sur le fond. Le voile gris autour du bloc laisse voir le vrai accueil. Fermer, cliquer autour ou Échap revient à l’accueil. Données locales : aucun réglage réel modifié ; hooks et diagnostics restent simulés.',
    frames: [BoardFrame(label: 'Accueil → feuille compacte', width: 700, child: SettingsTopPreview())],
  ),
];

/// The actual home and sheet lifecycle, with a local-only settings owner.
class SettingsTopPreview extends StatefulWidget {
  const SettingsTopPreview({
    super.key,
    this.initiallyOpen = false,
    this.muted = false,
    this.missingHooks = false,
    this.saveError = false,
  });
  final bool initiallyOpen, muted, missingHooks, saveError;

  @override
  State<SettingsTopPreview> createState() => _SettingsTopPreviewState();
}

class _SettingsTopPreviewState extends State<SettingsTopPreview> {
  final _window = GlobalKey();
  final _revision = ValueNotifier(0);
  late final _settings = Settings(sound: !widget.muted);
  late bool _error = widget.saveError;
  bool _autostart = true, _showing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show();
      });
    }
  }

  @override
  void dispose() {
    _revision.dispose();
    super.dispose();
  }

  void _change(void Function(Settings) update) {
    update(_settings);
    _revision.value++;
  }

  Future<void> _show() async {
    if (_showing) return;
    final within = _window.currentContext;
    if (within == null) return;
    _showing = true;
    try {
      await showSheetPage(
        within,
        builder: (sheet) => ValueListenableBuilder(
          valueListenable: _revision,
          builder: (_, _, _) => MikkyUiScope(
            ui: switch (_settings.theme) {
              ThemeChoice.auto => MikkyUi.of(sheet),
              ThemeChoice.light => MikkyUi.light,
              ThemeChoice.dark => MikkyUi.dark,
            },
            child: SettingsTopView(
              settings: _settings,
              autostart: _autostart,
              claude: widget.missingHooks ? SettingsHookState.missing : SettingsHookState.active,
              codex: widget.missingHooks ? SettingsHookState.missing : SettingsHookState.active,
              saveError: _error,
              actions: SettingsPageActions(
                back: () => Sheet.close(sheet),
                change: _change,
                setAutostart: (value) {
                  _autostart = value;
                  _revision.value++;
                },
                hooks: (_) {},
                diagnostics: () {},
                retrySave: () {
                  _error = false;
                  _revision.value++;
                },
              ),
            ),
          ),
        ),
      );
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => HomeFrame(
    layout: HomeLayout.top,
    child: OwnOverlay(
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.comma &&
              HardwareKeyboard.instance.isControlPressed) {
            _show();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onSecondaryTapUp: (_) => _show(),
          child: HomeView(
            key: _window,
            apps: sampleNotchApps,
            animate: false,
            onNew: () {},
            onSettings: (_) => unawaited(_show()),
          ),
        ),
      ),
    ),
  );
}

class _GlyphSamples extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Surface(
      width: 400,
      height: 92,
      color: ui.well,
      radius: Radii.lg,
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final (glyph, label) in [
            (SettingsGlyph.system, 'Système'),
            (SettingsGlyph.sun, 'Clair'),
            (SettingsGlyph.moon, 'Sombre'),
            (SettingsGlyph.positionTop, 'En haut'),
            (SettingsGlyph.positionRight, 'À droite'),
          ])
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PixelSettingsGlyph(glyph),
                const SizedBox(height: 8),
                Text(label, style: uiText(TextSize.caption, color: ui.text2)),
              ],
            ),
        ],
      ),
    );
  }
}

class PixelSliderTrial extends StatefulWidget {
  const PixelSliderTrial({super.key, required this.initial});
  final double initial;
  @override
  State<PixelSliderTrial> createState() => _PixelSliderTrialState();
}

class _PixelSliderTrialState extends State<PixelSliderTrial> {
  late double _value = widget.initial;
  @override
  Widget build(BuildContext context) => Surface(
    width: 200,
    height: 92,
    radius: Radii.lg,
    color: MikkyUi.of(context).well,
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${(_value * 100).round()} %',
          style: uiText(TextSize.caption, color: MikkyUi.of(context).text2, tabular: true),
        ),
        PixelSlider(value: _value, onChanged: (v) => setState(() => _value = v)),
      ],
    ),
  );
}
