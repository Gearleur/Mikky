import 'dart:ui';

/// What the user picked; [auto] follows Windows' light / dark setting.
enum ThemeChoice { auto, dark, light }

/// Agent status colors.
enum StatusColor { working, approval, finished, error, other }

/// The two validated island themes (`design/prototypes/ile-noir-et-blanc.html`,
/// `DARK` and `LIGHT`).
class MikkyTheme {
  const MikkyTheme._({
    required this.isLight,
    required this.foreground,
    required this.secondary,
    required this.faint,
    required this.button,
    required this.primary,
    required this.onPrimary,
    required this.keyHint,
    required this.code,
    required this.codeBorder,
    required this.error,
    required this.mikkyRim,
    required this._status,
  });

  /// Dark "A": the default.
  static const dark = MikkyTheme._(
    isLight: false,
    foreground: Color(0xF0FFFFFF),
    secondary: Color(0x75FFFFFF),
    faint: Color(0x12FFFFFF),
    button: Color(0x1CFFFFFF),
    primary: Color(0xFFF5F5F7),
    onPrimary: Color(0xFF0B0B0D),
    keyHint: Color(0x2EFFFFFF),
    code: Color(0x0DFFFFFF),
    codeBorder: Color(0x0FFFFFFF),
    error: Color(0xFFFF8D97),
    mikkyRim: Color(0x38FFFFFF),
    status: [Color(0xFF3B9EFF), Color(0xFFF5A524), Color(0xFF34D399), Color(0xFFF4505E), Color(0xFF8B5CF6)],
  );

  /// Light "pur": Apple system colors, no glow, no dots, no key hints.
  static const light = MikkyTheme._(
    isLight: true,
    foreground: Color(0xFF000000),
    secondary: Color(0x993C3C43),
    faint: Color(0x1F3C3C43),
    button: Color(0x1F767680),
    primary: Color(0xFF007AFF),
    onPrimary: Color(0xFFFFFFFF),
    keyHint: null,
    code: Color(0x14767680),
    codeBorder: Color(0x00000000),
    error: Color(0xFFFF3B30),
    mikkyRim: null,
    status: [Color(0xFF007AFF), Color(0xFFFF9500), Color(0xFF34C759), Color(0xFFFF3B30), Color(0xFFAF52DE)],
  );

  static MikkyTheme resolve(ThemeChoice choice, Brightness system) => switch (choice) {
        ThemeChoice.dark => dark,
        ThemeChoice.light => light,
        ThemeChoice.auto => system == Brightness.light ? light : dark,
      };

  final bool isLight;
  final Color foreground;
  final Color secondary;
  final Color faint;
  final Color button;
  final Color primary;
  final Color onPrimary;

  /// Border of the keyboard hints (N / Y). Null: no hints (light theme).
  final Color? keyHint;
  final Color code;
  final Color codeBorder;
  final Color error;

  /// Thin light outline that separates Mikky from the black island.
  final Color? mikkyRim;
  final List<Color> _status;

  /// Colored dots glow on black only.
  bool get glow => !isLight;

  Color status(StatusColor s) => _status[s.index];
}
