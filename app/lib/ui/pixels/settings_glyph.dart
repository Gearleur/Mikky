import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';
import 'pixel_fx.dart';

enum SettingsGlyph { system, sun, moon, positionTop, positionRight }

/// Settings signs in the same square pixels and four-tone palettes as
/// Mikky's status stars. The system sign is a joined day/night orb.
class PixelSettingsGlyph extends StatelessWidget {
  const PixelSettingsGlyph(this.glyph, {super.key, this.size = 20});

  final SettingsGlyph glyph;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SettingsGlyphPainter(glyph, MikkyUi.of(context)));
}

const _sun = [
  '....2....',
  '.3..2..3.',
  '..2.1.2..',
  '...101...',
  '221000122',
  '...101...',
  '..2.1.2..',
  '.3..2..3.',
  '....2....',
];
const _moon = [
  '....112..',
  '..1102...',
  '.1102....',
  '.1013....',
  '2103.....',
  '.2113....',
  '.2123....',
  '..22233..',
  '....333..',
];
const _system = [
  '....2.b..',
  '.3..2bc..',
  '..211abc.',
  '.2100ab..',
  '22100ab..',
  '.2100ab..',
  '..211abc.',
  '.3..2bcd.',
  '....2.cd.',
];
const _top = [
  '.ggggggggg.',
  '.g.32123.g.',
  '.g.......g.',
  '.g.......g.',
  '.g.......g.',
  '.g.......g.',
  '.ggggggggg.',
  '.....g.....',
  '...ggggg...',
  '...........',
  '...........',
];
const _right = [
  '.ggggggggg.',
  '.g.....3.g.',
  '.g.....2.g.',
  '.g.....1.g.',
  '.g.....2.g.',
  '.g.....3.g.',
  '.ggggggggg.',
  '.....g.....',
  '...ggggg...',
  '...........',
  '...........',
];

class _SettingsGlyphPainter extends CustomPainter {
  const _SettingsGlyphPainter(this.glyph, this.ui);

  final SettingsGlyph glyph;
  final MikkyUi ui;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = switch (glyph) {
      SettingsGlyph.system => _system,
      SettingsGlyph.sun => _sun,
      SettingsGlyph.moon => _moon,
      SettingsGlyph.positionTop => _top,
      SettingsGlyph.positionRight => _right,
    };
    final palette = switch (glyph) {
      SettingsGlyph.system || SettingsGlyph.sun => PixelFxPalette.yellow.on(ui),
      SettingsGlyph.moon => PixelFxPalette.violet.on(ui),
      _ => PixelFxPalette.signatureBlue.onWindow(ui),
    };
    final violet = PixelFxPalette.violet.on(ui);
    paintPixelGrid(canvas, size, rows.length, gap: .015, (x, y) {
      final code = rows[y].codeUnitAt(x);
      if (code >= 48 && code <= 51) return palette.levels[code - 48];
      if (code >= 97 && code <= 100) return violet.levels[code - 97];
      return code == 103 ? ui.text2 : null;
    });
  }

  @override
  bool shouldRepaint(_SettingsGlyphPainter old) => old.glyph != glyph || old.ui != ui;
}
