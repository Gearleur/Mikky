import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'tokens.dart';

/// The tools Mikky can run, and their logos (`assets/brands/`, see its
/// README for where they come from). Only Claude and Codex run today; the
/// others are ready for when they are added (idées 45, 46).
enum Brand {
  claude('Claude', 'claude-color.svg'),
  codex('Codex', 'openai.svg', 'openai-dark.svg'),
  opencode('OpenCode', 'opencode-logo-light-square.svg', 'opencode-logo-dark-square.svg'),
  pi('pi', 'pi.svg', 'pi-dark.svg'),
  openclaw('OpenClaw', 'openclaw.svg'),
  gemini('Gemini', 'gemini-color.svg');

  const Brand(this.label, this.light, [this.dark]);

  final String label;
  final String light;

  /// For the dark theme, when the mark is black.
  final String? dark;

  static Brand of(AgentProvider provider) => switch (provider) {
        AgentProvider.claude => claude,
        AgentProvider.codex => codex,
      };
}

/// A tool's logo, [size] px square, for the current theme.
class BrandLogo extends StatelessWidget {
  const BrandLogo(this.brand, {super.key, this.size = 14});

  final Brand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = !MikkyUi.of(context).isLight;
    final file = dark ? (brand.dark ?? brand.light) : brand.light;
    return SvgPicture.asset('assets/brands/$file', width: size, height: size, semanticsLabel: brand.label);
  }
}
