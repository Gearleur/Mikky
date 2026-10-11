import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'canvas.dart';

/// Simple logos (2026-10-06, after SFEIR's: a mascot, a symbol and a
/// name in brackets; « un logo plus simple… pour l'entreprise »): Mikky's
/// symbol and his name in letters, as trials. Mikky's own marks: his two
/// tall eyes, his ears, brackets for the computer, pixels.
enum MarkSymbol {
  // Kept from the first trials (2026-10-06, « j'aime bien »).
  ears('Crochets-oreilles', 'Le haut des crochets se lève en oreilles : sa tête, faite de crochets.'),
  monogram('M-oreilles', 'Un M dont les deux pointes sont ses oreilles, ses yeux dessous.');

  const MarkSymbol(this.label, this.note);

  final String label, note;
}

/// The mark on a square tile: white on black (as SFEIR's), or black on
/// white.
class MarkTile extends StatelessWidget {
  const MarkTile(this.symbol, {super.key, this.size = 120, this.dark = true});

  final MarkSymbol symbol;
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: dark ? const Color(0xFF0C0C0E) : const Color(0xFFFFFFFF),
      border: dark ? null : Border.all(color: const Color(0x1F000000)),
    ),
    child: CustomPaint(
      painter: _MarkPainter(
        symbol,
        dark ? const Color(0xFFFFFFFF) : const Color(0xFF0C0C0E),
        dark ? const Color(0xFF0C0C0E) : const Color(0xFFFFFFFF),
      ),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.symbol, this.ink, this.paper);

  final MarkSymbol symbol;
  final Color ink;

  /// The tile's color: what shows through (eyes cut out of a full shape).
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final fill = Paint()..color = ink;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, s * .085)
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    // His eyes: two tall rounded bars, a little apart; [cut]: in the
    // tile's color, out of a full shape.
    void eyes(double cy, double h, double gap, {bool cut = false, double cx = .5}) {
      final w = math.max(1.5, s * .1);
      for (final side in const [-1.0, 1.0]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(s * cx + side * gap, cy), width: w, height: h),
            Radius.circular(w / 2),
          ),
          cut ? (Paint()..color = paper) : fill,
        );
      }
    }

    switch (symbol) {
      case MarkSymbol.ears:
        final top = s * .34, bottom = s * .78, serif = s * .12;
        for (final side in const [-1.0, 1.0]) {
          final x = s / 2 + side * s * .3;
          // The bracket's top rises into an ear, then comes back in.
          canvas.drawPath(
            Path()
              ..moveTo(x - side * serif, bottom)
              ..lineTo(x, bottom)
              ..lineTo(x, top)
              ..lineTo(x - side * s * .02, s * .16)
              ..lineTo(x - side * serif * 1.6, top),
            stroke..strokeJoin = StrokeJoin.round,
          );
        }
        eyes(s * .56, s * .22, s * .095);
      case MarkSymbol.monogram:
        final l = s * .2, r = s * .8, t = s * .2, b = s * .66;
        // M: its two points up like ears, its middle dipping between them.
        canvas.drawPath(
          Path()
            ..moveTo(l, b)
            ..lineTo(l + s * .03, t)
            ..lineTo(s / 2, s * .46)
            ..lineTo(r - s * .03, t)
            ..lineTo(r, b),
          stroke..strokeJoin = StrokeJoin.round,
        );
        eyes(s * .78, s * .12, s * .095);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.symbol != symbol || old.ink != ink || old.paper != paper;
}

/// Mikky's name in letters.
enum MarkWord {
  bracketed('[mikky]', 'Son nom entre crochets, en Geist Mono.'),
  eyes('[m] et ses yeux', 'Court : « m » et ses deux yeux, entre crochets ; aussi un symbole.');

  const MarkWord(this.label, this.note);

  final String label, note;
}

/// The name on a band: white on black (SFEIR's banner) or black on white.
class MarkName extends StatelessWidget {
  const MarkName(this.word, {super.key, this.height = 90, this.dark = true});

  final MarkWord word;
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xFFFFFFFF) : const Color(0xFF0C0C0E);
    final h = height;
    TextStyle mono(double size) => TextStyle(
      fontFamily: 'Geist Mono',
      fontSize: size,
      fontWeight: FontWeight.w500,
      color: ink,
      height: 1,
      letterSpacing: -size * .02,
    );
    // One of his eyes, standing in for a letter: on the baseline, a little
    // taller than the small letters, like his own tall eyes.
    InlineSpan eye(double size) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: size * .07),
        child: Container(
          width: size * .17,
          height: size * .64,
          decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(size)),
        ),
      ),
    );
    final f = h * .42;
    final child = switch (word) {
      MarkWord.bracketed => Text('[mikky]', style: mono(f)),
      MarkWord.eyes => Text.rich(
        TextSpan(
          style: mono(f),
          children: [
            const TextSpan(text: '[m'),
            eye(f),
            eye(f),
            const TextSpan(text: ']'),
          ],
        ),
      ),
    };
    return Container(
      height: h,
      padding: EdgeInsets.symmetric(horizontal: h * .45),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0C0C0E) : const Color(0xFFFFFFFF),
        border: dark ? null : Border.all(color: const Color(0x1F000000)),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// A symbol on black and on white, then at the sizes it must hold (the
/// taskbar, the notification area).
class MarkSymbolSheet extends StatelessWidget {
  const MarkSymbolSheet(this.symbol, {super.key});

  final MarkSymbol symbol;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [MarkTile(symbol), const SizedBox(width: 10), MarkTile(symbol, dark: false)],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (px, dark) in const [
              (48.0, true),
              (32.0, true),
              (24.0, false),
              (16.0, true),
              (16.0, false),
            ]) ...[
              SizeSample(
                px,
                child: MarkTile(symbol, size: px, dark: dark),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }
}
