import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'brand_logo.dart';
import 'icons.dart';
import 'side.dart';
import 'tokens.dart';

/// The sign of the software a task runs in (2026-10-05): ours for VS Code
/// and the terminal (their logos are not ours to ship; the installed VS
/// Code's icon could come later), the tool's logo for its own app, Mikky
/// for his own agents.
class AppGlyph extends StatelessWidget {
  const AppGlyph(this.app, {super.key, this.size = 14});

  final AgentApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return switch (app) {
      AgentApp.vscode => MikkyIcon('code', size: size, color: ui.blue, stroke: 2),
      AgentApp.terminal => MikkyIcon('agents', size: size, color: ui.text2),
      AgentApp.claude => BrandLogo(Brand.claude, size: size),
      AgentApp.codex => BrandLogo(Brand.codex, size: size),
      AgentApp.mikky => SizedBox.square(
        dimension: size,
        child: OverflowBox(maxWidth: size * 1.4, maxHeight: size * 1.4, child: MiniMikky(size: size * 1.4, animate: false, badge: false)),
      ),
    };
  }
}

/// The software's sign and name, on one line.
class AppLine extends StatelessWidget {
  const AppLine(this.app, {super.key});

  final AgentApp app;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AppGlyph(app),
      const SizedBox(width: 6),
      Text(app.label, style: uiText(TextSize.small, weight: FontWeight.w600, color: ui.text2)),
    ]);
  }
}
