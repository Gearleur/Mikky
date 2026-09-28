import 'dart:ui';

/// What the user picked; [auto] follows Windows' light / dark setting.
enum ThemeChoice { auto, dark, light }

/// The two validated island themes (`design/prototypes/ile-noir-et-blanc.html`).
class MikkyTheme {
  const MikkyTheme._({required this.isLight, required this.foreground, required this.secondary, required this.mikkyRim});

  /// Dark "A": the default.
  static const dark = MikkyTheme._(
    isLight: false,
    foreground: Color(0xF0FFFFFF),
    secondary: Color(0x75FFFFFF),
    mikkyRim: Color(0x38FFFFFF),
  );

  /// Light "pur": Apple system colors, no glow, no dots, no key hints.
  static const light = MikkyTheme._(
    isLight: true,
    foreground: Color(0xFF000000),
    secondary: Color(0x993C3C43),
    mikkyRim: null,
  );

  static MikkyTheme resolve(ThemeChoice choice, Brightness system) => switch (choice) {
        ThemeChoice.dark => dark,
        ThemeChoice.light => light,
        ThemeChoice.auto => system == Brightness.light ? light : dark,
      };

  final bool isLight;
  final Color foreground;
  final Color secondary;

  /// Thin light outline that separates Mikky from the black island.
  final Color? mikkyRim;
}
