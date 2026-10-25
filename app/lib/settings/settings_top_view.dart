import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../settings.dart';
import '../theme.dart';
import '../ui/brand/brand_logo.dart';
import '../ui/controls/pixel_slider.dart';
import '../ui/foundation/icons.dart';
import '../ui/foundation/motion.dart';
import '../ui/foundation/surface.dart';
import '../ui/foundation/tokens.dart';
import '../ui/pixels/settings_glyph.dart';
import 'settings_controls.dart';
import 'settings_view.dart';

/// Compact settings in the top notch's existing 700 × 200 home.
/// The sheet owner supplies the history's blur, backdrop and dismissal.
/// No navigation rail: that layout is deliberately left for later.
class SettingsTopView extends StatelessWidget {
  const SettingsTopView({
    super.key,
    required this.settings,
    required this.actions,
    required this.autostart,
    this.claude = SettingsHookState.unknown,
    this.codex = SettingsHookState.unknown,
    this.saveError = false,
    this.errorMessage,
  });

  final Settings settings;
  final SettingsPageActions actions;
  final bool autostart, saveError;
  final String? errorMessage;
  final SettingsHookState claude, codex;

  static const inset = 12.0;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final s = settings;
    final groups = [
      _CompactGroup('Apparence', [
        _GlyphChoice(
          label: 'Thème',
          value: switch (s.theme) {
            ThemeChoice.auto => 'Système',
            ThemeChoice.light => 'Clair',
            ThemeChoice.dark => 'Sombre',
          },
          choices: [
            for (final (theme, glyph, label) in [
              (ThemeChoice.auto, SettingsGlyph.system, 'Système'),
              (ThemeChoice.light, SettingsGlyph.sun, 'Clair'),
              (ThemeChoice.dark, SettingsGlyph.moon, 'Sombre'),
            ])
              _GlyphOption(
                label: 'Thème $label',
                glyph: glyph,
                selected: s.theme == theme,
                onTap: () => actions.change((s) => s.theme = theme),
              ),
          ],
        ),
        const SizedBox(height: 5),
        _GlyphChoice(
          label: 'Position',
          value: s.edge == IslandEdge.top ? 'En haut' : 'À droite',
          choices: [
            for (final (edge, glyph, label) in [
              (IslandEdge.top, SettingsGlyph.positionTop, 'En haut'),
              (IslandEdge.right, SettingsGlyph.positionRight, 'À droite'),
            ])
              _GlyphOption(
                label: 'Position $label',
                glyph: glyph,
                selected: s.edge == edge,
                onTap: () => actions.change((s) => s.edge = edge),
              ),
          ],
        ),
      ]),
      _CompactGroup('Sons et alertes', [
        _CompactToggle('Sons', value: s.sound, onChanged: (v) => actions.change((s) => s.sound = v)),
        Row(
          children: [
            Expanded(child: _text('Volume', ui.text2)),
            _text('${(s.volume * 100).round()} %', ui.text2, small: true),
          ],
        ),
        PixelSlider(value: s.volume, onChanged: s.sound ? (v) => actions.change((s) => s.volume = v) : null),
        _CompactToggle(
          'Notifications',
          value: s.notifications,
          onChanged: (v) => actions.change((s) => s.notifications = v),
        ),
      ]),
      _CompactGroup('Agents', [
        for (final (provider, state) in [(AgentProvider.claude, claude), (AgentProvider.codex, codex)])
          _CompactAction(
            provider == AgentProvider.claude ? 'Claude' : 'Codex',
            leading: BrandLogo(Brand.of(provider), size: 13),
            value: switch (state) {
              SettingsHookState.active => 'Activés',
              SettingsHookState.missing => 'Absents',
              SettingsHookState.outdated => 'À revoir',
              SettingsHookState.unknown => 'À vérifier',
            },
            semanticValue: state.label,
            onTap: () => actions.hooks(provider),
          ),
        _CompactToggle(
          'Relance auto',
          value: s.autoRelaunch,
          onChanged: (v) => actions.change((s) => s.autoRelaunch = v),
        ),
        _text('Mikky doit rester ouvert.', ui.text2, small: true),
      ]),
      _CompactGroup('Général', [
        _CompactToggle('Au démarrage', value: autostart, onChanged: actions.setAutostart),
        _CompactToggle('Raccourcis', value: s.hotkeys, onChanged: (v) => actions.change((s) => s.hotkeys = v)),
        _CompactAction('Diagnostics', onTap: actions.diagnostics),
        _text('Ctrl + virgule · paramètres', ui.text2, small: true),
      ]),
    ];
    return Padding(
      padding: const EdgeInsets.all(inset),
      child: Surface(
        radius: Radii.xl,
        color: ui.island,
        shadows: ui.floating,
        padding: const EdgeInsets.fromLTRB(14, 6, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  Text(
                    'Paramètres',
                    style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text),
                  ),
                  const Spacer(),
                  if (saveError) ...[
                    _text(errorMessage ?? 'Sauvegarde impossible', ui.red, small: true),
                    const SizedBox(width: 8),
                    if (actions.retrySave != null)
                      SettingActivator(
                        label: 'Réessayer la sauvegarde',
                        onPressed: actions.retrySave,
                        child: GestureDetector(
                          onTap: actions.retrySave,
                          child: _text('Réessayer', ui.text, small: true),
                        ),
                      ),
                    const SizedBox(width: 12),
                  ],
                  SettingActivator(
                    label: 'Fermer les paramètres',
                    onPressed: actions.back,
                    child: GestureDetector(
                      onTap: actions.back,
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox.square(
                        dimension: 24,
                        child: Center(child: MikkyIcon('x', size: 13, color: ui.text2)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(width: 9),
                      Container(width: 1, color: ui.line),
                      const SizedBox(width: 9),
                    ],
                    Expanded(child: groups[i]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _text(String text, Color color, {bool small = false}) =>
    Text(text, style: uiText(small ? TextSize.code : TextSize.caption, color: color, height: 1.3));

class _CompactGroup extends StatelessWidget {
  const _CompactGroup(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: uiText(TextSize.caption, color: MikkyUi.of(context).text2, weight: FontWeight.w600, height: 1.3),
      ),
      const SizedBox(height: 6),
      ...children,
    ],
  );
}

class _GlyphChoice extends StatelessWidget {
  const _GlyphChoice({required this.label, required this.value, required this.choices});
  final String label, value;
  final List<Widget> choices;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _text(label, ui.text)),
            _text(value, ui.text2, small: true),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            for (var i = 0; i < choices.length; i++) ...[if (i > 0) const SizedBox(width: 4), choices[i]],
          ],
        ),
      ],
    );
  }
}

class _GlyphOption extends StatelessWidget {
  const _GlyphOption({required this.label, required this.glyph, required this.selected, required this.onTap});
  final String label;
  final SettingsGlyph glyph;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SettingActivator(
      label: label,
      selected: selected,
      onPressed: onTap,
      child: HoverBuilder(
        builder: (_, hover) => Pressable(
          onTap: onTap,
          child: Surface(
            width: 28,
            height: 28,
            radius: Radii.sm,
            color: selected
                ? ui.thumb
                : hover
                ? ui.hover
                : null,
            shadows: selected ? ui.shThumb : const [],
            child: Center(child: PixelSettingsGlyph(glyph)),
          ),
        ),
      ),
    );
  }
}

class _CompactToggle extends StatelessWidget {
  const _CompactToggle(this.label, {required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final toggle = onChanged == null ? null : () => onChanged!(!value);
    return SettingActivator(
      label: label,
      toggled: value,
      onPressed: toggle,
      child: Pressable(
        onTap: toggle,
        pressedScale: .99,
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              Expanded(child: _text(label, ui.text)),
              const SizedBox(width: 6),
              Surface(
                width: 28,
                height: 16,
                color: value ? ui.ink : ui.track,
                shadows: value ? const [] : ui.inset,
                padding: const EdgeInsets.all(2),
                child: AnimatedAlign(
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  duration: Motion.of(context, Motion.hover),
                  curve: Curves.easeOut,
                  child: Surface(width: 12, height: 12, color: value ? ui.onInk : ui.knob, shadows: ui.shThumb),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction(this.label, {required this.onTap, this.leading, this.value, this.semanticValue});
  final String label;
  final VoidCallback onTap;
  final Widget? leading;
  final String? value, semanticValue;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SettingActivator(
      label: label,
      value: semanticValue,
      onPressed: onTap,
      child: HoverBuilder(
        builder: (_, hover) => Pressable(
          onTap: onTap,
          pressedScale: .99,
          child: Container(
            height: 26,
            decoration: BoxDecoration(color: hover ? ui.hover : null, borderRadius: BorderRadius.circular(6)),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],
                Expanded(child: _text(label, ui.text)),
                if (value != null) ...[_text(value!, ui.text2, small: true), const SizedBox(width: 5)],
                MikkyIcon('right', size: 12, color: ui.text2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
