import 'dart:ui';

import 'package:mikky_engine/mikky_engine.dart';

/// What the user picked; [auto] follows Windows' light / dark setting.
enum ThemeChoice { auto, dark, light }

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

  /// Dark "A": the default. The prototype's colors, plus the states it did
  /// not show (spec §5.2 table).
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
    status: {
      AgentStatus.working: Color(0xFF3B9EFF),
      AgentStatus.thinking: Color(0xFF8B5CF6),
      AgentStatus.searching: Color(0xFF6E7BFF),
      AgentStatus.approval: Color(0xFFF5A524),
      AgentStatus.question: Color(0xFF22D3EE),
      AgentStatus.error: Color(0xFFF4505E),
      AgentStatus.finished: Color(0xFF34D399),
      AgentStatus.rateLimited: Color(0xFFFB923C),
      AgentStatus.idle: Color(0x75FFFFFF),
    },
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
    status: {
      AgentStatus.working: Color(0xFF007AFF),
      AgentStatus.thinking: Color(0xFFAF52DE),
      AgentStatus.searching: Color(0xFF5856D6),
      AgentStatus.approval: Color(0xFFFF9500),
      AgentStatus.question: Color(0xFF32ADE6),
      AgentStatus.error: Color(0xFFFF3B30),
      AgentStatus.finished: Color(0xFF34C759),
      AgentStatus.rateLimited: Color(0xFFFFCC00),
      AgentStatus.idle: Color(0x993C3C43),
    },
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
  final Map<AgentStatus, Color> _status;

  /// Colored dots glow on black only.
  bool get glow => !isLight;

  Color status(AgentStatus s) => _status[s]!;
}
