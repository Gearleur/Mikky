import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikky/mikky/mikky_painter.dart';
import 'package:mikky/theme.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// Golden image of Mikky in every state and emote, at a fixed time
/// (spec §9). Update with `flutter test --update-goldens`.
Future<void> _loadFonts() async {
  for (final (family, files) in [
    ('Geist', ['Geist-Regular.ttf', 'Geist-SemiBold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }
}

Mikky _mikkyAt({MikkyState? state, MikkyEmote? emote, double seconds = .9}) {
  final m = Mikky(random: math.Random(7));
  if (state != null) m.setState(state);
  if (emote != null) m.play(emote);
  for (var i = 0; i < (seconds * 60).round(); i++) {
    m.update(1 / 60, lookX: .2, lookY: .1);
  }
  return m;
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.mikky, required this.theme});

  final String label;
  final Mikky mikky;
  final MikkyTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        width: 170,
        height: 190,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.isLight ? const Color(0xFFEEE9E1) : const Color(0xFF070708),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: MikkyPainter(
                  geometry: MikkyGeometry.of(mikky, 48),
                  center: const Offset(85, 100),
                  rim: theme.mikkyRim,
                  statusColor: theme.status,
                  foreground: theme.foreground,
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 8,
              child: Text(label, style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: theme.foreground)),
            ),
          ],
        ),
      );
}

void main() {
  setUpAll(_loadFonts);

  for (final theme in [MikkyTheme.light, MikkyTheme.dark]) {
    final name = theme.isLight ? 'light' : 'dark';
    testWidgets('Mikky expressions ($name)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1070, 620));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: theme.isLight ? Colors.white : const Color(0xFF1C1C1E),
            child: Wrap(
              children: [
                for (final s in MikkyState.values) _Cell(label: s.name, mikky: _mikkyAt(state: s), theme: theme),
                for (final e in MikkyEmote.values)
                  _Cell(label: 'émote ${e.name}', mikky: _mikkyAt(emote: e, seconds: .5), theme: theme),
              ],
            ),
          ),
        ),
      );
      await expectLater(find.byType(Wrap), matchesGoldenFile('goldens/mikky_expressions_$name.png'));
    });
  }
}
