import 'package:flutter/widgets.dart';

import '../ui/controls/buttons.dart';
import 'settings_controls.dart';

/// Icon only on the home, with a keyboard stop and an accessible name.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.onPressed, this.size = 24});

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => SettingActivator(
    label: 'Paramètres',
    onPressed: onPressed,
    child: RoundButton('sliders', size: size, iconSize: 13, ghost: true, tooltip: 'Paramètres', onPressed: onPressed),
  );
}
