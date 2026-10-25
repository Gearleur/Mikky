import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../settings.dart';
import '../theme.dart';
import '../ui/foundation/icons.dart';
import '../ui/foundation/motion.dart';
import '../ui/foundation/surface.dart';
import '../ui/foundation/tokens.dart';
import 'settings_controls.dart';
import 'settings_view.dart';

enum QuickSettingsSection { theme, position }

/// Compact global menu, separate from an agent's own actions. The owner
/// places and dismisses it; both this menu and the page share its state.
class QuickSettingsMenu extends StatefulWidget {
  const QuickSettingsMenu({
    super.key,
    required this.settings,
    required this.change,
    required this.openSettings,
    required this.closeApp,
    required this.dismiss,
    this.initialSection,
    this.autofocus = false,
    this.compact = false,
  });

  final Settings settings;
  final ChangeSettings change;
  final VoidCallback openSettings, closeApp, dismiss;
  final QuickSettingsSection? initialSection;
  final bool autofocus;
  final bool compact;

  @override
  State<QuickSettingsMenu> createState() => _QuickSettingsMenuState();
}

class _QuickSettingsMenuState extends State<QuickSettingsMenu> {
  late QuickSettingsSection? _section = widget.initialSection;
  final _root = List.generate(6, (_) => FocusNode());
  final _sub = List.generate(3, (_) => FocusNode());

  @override
  void dispose() {
    for (final node in [..._root, ..._sub]) {
      node.dispose();
    }
    super.dispose();
  }

  void _open(QuickSettingsSection section) {
    setState(() => _section = section);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _section == section) _sub.first.requestFocus();
    });
  }

  void _back() {
    final index = _section == QuickSettingsSection.theme ? 1 : 2;
    setState(() => _section = null);
    _root[index].requestFocus();
  }

  KeyEventResult _key(KeyEvent event, int index, {bool submenu = false}) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_section != null) {
        _back();
      } else {
        widget.dismiss();
      }
    } else if (key == LogicalKeyboardKey.arrowLeft && submenu) {
      _back();
    } else if (key == LogicalKeyboardKey.arrowRight && !submenu && (index == 1 || index == 2)) {
      _open(index == 1 ? QuickSettingsSection.theme : QuickSettingsSection.position);
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      final nodes = submenu ? _sub.take(_section == QuickSettingsSection.theme ? 3 : 2).toList() : _root;
      nodes[(index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) % nodes.length].requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _change(void Function(Settings) update) {
    widget.change(update);
    widget.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final ui = MikkyUi.of(context);
    Widget rootRow(
      int index,
      String label,
      VoidCallback onTap, {
      String? value,
      bool? checked,
      String? detail,
      String? icon,
    }) => _MenuRow(
      label: label,
      value: value,
      checked: checked,
      detail: detail,
      icon: icon,
      onTap: onTap,
      focusNode: _root[index],
      autofocus: widget.autofocus && index == 0,
      onKey: (_, event) => _key(event, index),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.compact || _section == null)
          _MenuPanel(
            width: 252,
            children: [
              rootRow(0, 'Paramètres…', widget.openSettings, icon: 'sliders'),
              rootRow(
                1,
                'Thème',
                () => _open(QuickSettingsSection.theme),
                value: switch (s.theme) {
                  ThemeChoice.auto => 'Auto',
                  ThemeChoice.light => 'Clair',
                  ThemeChoice.dark => 'Sombre',
                },
                icon: 'right',
              ),
              rootRow(
                2,
                'Position',
                () => _open(QuickSettingsSection.position),
                value: s.edge == IslandEdge.top ? 'En haut' : 'À droite',
                icon: 'right',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Container(height: 1, color: ui.line),
              ),
              rootRow(3, 'Sons', () => _change((s) => s.sound = !s.sound), checked: s.sound),
              rootRow(
                4,
                'Notifications',
                () => _change((s) => s.notifications = !s.notifications),
                checked: s.notifications,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Container(height: 1, color: ui.line),
              ),
              rootRow(5, 'Fermer Mikky', widget.closeApp, detail: 'Les agents continuent'),
            ],
          ),
        if (_section != null) ...[
          if (!widget.compact) const SizedBox(width: 6),
          Padding(
            padding: EdgeInsets.only(
              top: widget.compact
                  ? 0
                  : _section == QuickSettingsSection.theme
                  ? 36
                  : 72,
            ),
            child: _MenuPanel(
              width: widget.compact ? 252 : 164,
              children: [
                if (widget.compact)
                  SettingAction(
                    _section == QuickSettingsSection.theme ? 'Thème · retour' : 'Position · retour',
                    onPressed: _back,
                  ),
                for (var i = 0; i < (_section == QuickSettingsSection.theme ? 3 : 2); i++)
                  _MenuRow(
                    label: (_section == QuickSettingsSection.theme
                        ? const ['Automatique', 'Clair', 'Sombre']
                        : const ['En haut', 'À droite'])[i],
                    checked: _section == QuickSettingsSection.theme
                        ? s.theme == [ThemeChoice.auto, ThemeChoice.light, ThemeChoice.dark][i]
                        : (s.edge == IslandEdge.top ? 0 : 1) == i,
                    onTap: () {
                      if (_section == QuickSettingsSection.theme) {
                        _change((s) => s.theme = [ThemeChoice.auto, ThemeChoice.light, ThemeChoice.dark][i]);
                      } else {
                        _change((s) => s.edge = i == 0 ? IslandEdge.top : IslandEdge.right);
                      }
                    },
                    focusNode: _sub[i],
                    onKey: (_, event) => _key(event, i, submenu: true),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.width, required this.children});

  final double width;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Surface(
      width: width,
      color: ui.island,
      radius: Radii.xl,
      shadows: ui.floating,
      padding: const EdgeInsets.all(6),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.onTap,
    required this.focusNode,
    required this.onKey,
    this.value,
    this.checked,
    this.detail,
    this.icon,
    this.autofocus = false,
  });

  final String label;
  final String? value, detail, icon;
  final bool? checked;
  final VoidCallback onTap;
  final FocusNode focusNode;
  final FocusOnKeyEventCallback onKey;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return SettingActivator(
      label: label,
      value: value ?? detail,
      toggled: checked,
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: onKey,
      onPressed: onTap,
      child: HoverBuilder(
        builder: (context, hover) => Pressable(
          onTap: onTap,
          pressedScale: .99,
          child: Container(
            decoration: BoxDecoration(color: hover ? ui.well : null, borderRadius: BorderRadius.circular(Radii.md)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Expanded(child: SettingLabel(label, detail: detail)),
                if (value != null) ...[
                  const SizedBox(width: 10),
                  Text(value!, style: uiText(TextSize.caption, color: ui.text2)),
                ],
                const SizedBox(width: 10),
                SizedBox.square(
                  dimension: 16,
                  child: checked == true || icon != null
                      ? MikkyIcon(checked == true ? 'check' : icon!, size: 16, color: ui.text2)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
