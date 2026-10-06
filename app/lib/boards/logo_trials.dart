import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/tokens.dart';

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
          painter: _MarkPainter(symbol, dark ? const Color(0xFFFFFFFF) : const Color(0xFF0C0C0E), dark ? const Color(0xFF0C0C0E) : const Color(0xFFFFFFFF)),
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
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s * cx + side * gap, cy), width: w, height: h), Radius.circular(w / 2)),
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
    TextStyle mono(double size) => TextStyle(fontFamily: 'Geist Mono', fontSize: size, fontWeight: FontWeight.w500, color: ink, height: 1, letterSpacing: -size * .02);
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
      MarkWord.eyes => Text.rich(TextSpan(style: mono(f), children: [const TextSpan(text: '[m'), eye(f), eye(f), const TextSpan(text: ']')])),
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
    final ui = MikkyUi.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        MarkTile(symbol),
        const SizedBox(width: 10),
        MarkTile(symbol, dark: false),
      ]),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        for (final (px, dark) in const [(48.0, true), (32.0, true), (24.0, false), (16.0, true), (16.0, false)]) ...[
          Column(mainAxisSize: MainAxisSize.min, children: [
            MarkTile(symbol, size: px, dark: dark),
            const SizedBox(height: 4),
            Text('${px.round()}', style: uiText(TextSize.badge, color: ui.text3, tabular: true)),
          ]),
          const SizedBox(width: 10),
        ],
      ]),
    ]);
  }
}

/// Logos made smooth (2026-10-06, « aucun n'est bien… pense pro, avec une
/// touche de magie, garde notre DA, lisse, lisible ; juste la forme de
/// Mikky hyper simple, ou sa magie »): his real silhouette, clean (no fur,
/// round ear tips), and one magic touch at most.
enum SmoothMark {
  silhouette('Silhouette', 'Sa forme exacte, lissée : sa tête, ses deux oreilles, ses yeux en creux. Rien d’autre.'),
  sparkle('Silhouette et étincelle', 'La même, et une petite étincelle à quatre branches près d’une oreille : la touche magique.'),
  eyes('Son regard', 'Seulement ses deux yeux hauts, avec un éclat dans chacun : on le reconnaît à son regard.'),
  bolt('L’éclair', 'Sa silhouette, un petit éclair sur le front : le sorcier (Harry Potter), très discret.'),
  moon('Dans la lune', 'Sa silhouette dans une pleine lune : le chat du sorcier, la nuit.'),
  dots('Pixels ronds', 'Sa silhouette faite de petits points ronds réguliers : le pixel, en doux.'),
  line('Un seul trait', 'Son contour d’un trait continu, ses yeux pleins : net, comme un pictogramme.');

  const SmoothMark(this.label, this.note);

  final String label, note;
}

/// His clean outline, centered at [c], for a radius [r]: his superellipse
/// head, its bottom a little wider, two ears with round tips.
Path mikkyOutline(Offset c, double r, {int points = 240}) {
  final tu = MikkyTuning.defaults;
  final rx = r * MikkyShape.halfWidth, ry = r * MikkyShape.halfHeight;
  const ex = 2 / MikkyShape.exponent;
  double ear(double x) {
    var best = 0.0;
    for (final side in const [-1.0, 1.0]) {
      final d = x - side * rx * tu.earCenter;
      final half = (d * side > 0 ? MikkyShape.earOuterHalfWidth : MikkyShape.earInnerHalfWidth) * rx * tu.earWidth;
      final tri = (1 - d.abs() / half).clamp(0.0, 1.0);
      // A rounder tip than his own: smooth at small sizes.
      final round = tri > .82 ? .82 + (tri - .82) * .35 : tri;
      best = math.max(best, tu.earHeight * r * math.pow(round / .8829, 1.05));
    }
    return best;
  }

  final path = Path();
  for (var i = 0; i <= points; i++) {
    final th = i / points * math.pi * 2;
    final cs = math.cos(th), sn = math.sin(th);
    final px = cs.sign * math.pow(cs.abs(), ex), py = sn.sign * math.pow(sn.abs(), ex);
    var x = rx * px * (1 + tu.bottomWiden * py);
    var y = ry * py;
    if (py < 0) y -= ear(x) * (-py / .3).clamp(0.0, 1.0);
    final p = c + Offset(x, y);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// His eyes for a radius [r], centered at [c]: tall ovals, as he looks
/// ahead.
List<Rect> mikkyEyes(Offset c, double r) {
  final tu = MikkyTuning.defaults;
  final rx = r * MikkyShape.halfWidth, ry = r * MikkyShape.halfHeight;
  final w = r * MikkyShape.eyeWidth * tu.eyeSize, h = r * MikkyShape.eyeBaseHeight * tu.eyeElongation * tu.eyeSize;
  final y = -math.sin(tu.eyeElevation) * ry;
  return [
    for (final side in const [-1.0, 1.0])
      Rect.fromCenter(center: c + Offset(math.sin(side * tu.eyeSpread) * math.cos(tu.eyeElevation) * rx, y), width: w * math.cos(tu.eyeSpread), height: h),
  ];
}

/// A four-pointed sparkle at [c], [o] from its middle to a point.
Path sparklePath(Offset c, double o) {
  final i = o * .22;
  return Path()
    ..moveTo(c.dx, c.dy - o)
    ..quadraticBezierTo(c.dx + i, c.dy - i, c.dx + o, c.dy)
    ..quadraticBezierTo(c.dx + i, c.dy + i, c.dx, c.dy + o)
    ..quadraticBezierTo(c.dx - i, c.dy + i, c.dx - o, c.dy)
    ..quadraticBezierTo(c.dx - i, c.dy - i, c.dx, c.dy - o)
    ..close();
}

/// A smooth mark on a tile with soft corners.
class SmoothTile extends StatelessWidget {
  const SmoothTile(this.mark, {super.key, this.size = 120, this.dark = true});

  final SmoothMark mark;
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF0C0C0E) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(size * .22),
          border: dark ? null : Border.all(color: const Color(0x1F000000)),
        ),
        child: CustomPaint(painter: _SmoothPainter(mark, dark)),
      );
}

class _SmoothPainter extends CustomPainter {
  _SmoothPainter(this.mark, this.dark);

  final SmoothMark mark;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final ink = dark ? const Color(0xFFFFFFFF) : const Color(0xFF0C0C0E);
    final paper = dark ? const Color(0xFF0C0C0E) : const Color(0xFFFFFFFF);
    final fill = Paint()..color = ink;
    final hole = Paint()..color = paper;
    final r = s * .27;
    final c = Offset(s / 2, s * .58);
    void eyesIn(Paint paint, {Offset at = Offset.zero, double scale = 1}) {
      for (final e in mikkyEyes(c + at, r * scale)) {
        canvas.drawOval(e, paint);
      }
    }

    switch (mark) {
      case SmoothMark.silhouette:
        canvas.drawPath(mikkyOutline(c, r), fill);
        eyesIn(hole);
      case SmoothMark.sparkle:
        final at = Offset(-s * .04, s * .02);
        canvas.drawPath(mikkyOutline(c + at, r), fill);
        eyesIn(hole, at: at);
        canvas.drawPath(sparklePath(Offset(s * .8, s * .2), s * .085), fill);
      case SmoothMark.eyes:
        final big = r * 2.4;
        // His eyes sit above his center: put them in the middle of the tile.
        final lift = math.sin(MikkyTuning.defaults.eyeElevation) * MikkyShape.halfHeight * big;
        for (final e in mikkyEyes(Offset(s / 2, s / 2 + lift), big)) {
          canvas.drawOval(e, fill);
          // A glint up in each eye.
          canvas.drawOval(Rect.fromCenter(center: e.topCenter + Offset(-e.width * .1, e.height * .24), width: e.width * .42, height: e.height * .2), hole);
        }
      case SmoothMark.bolt:
        canvas.drawPath(mikkyOutline(c, r), fill);
        eyesIn(hole);
        // A small lightning bolt on his forehead.
        final b = Offset(s / 2, c.dy - r * .78), u = r * .2;
        canvas.drawPath(
          Path()
            ..moveTo(b.dx + u * .35, b.dy - u)
            ..lineTo(b.dx - u * .45, b.dy + u * .1)
            ..lineTo(b.dx + u * .05, b.dy + u * .1)
            ..lineTo(b.dx - u * .35, b.dy + u)
            ..lineTo(b.dx + u * .45, b.dy - u * .15)
            ..lineTo(b.dx - u * .05, b.dy - u * .15)
            ..close(),
          hole,
        );
      case SmoothMark.moon:
        // A full moon, and him inside it, in the tile's color.
        canvas.drawCircle(Offset(s / 2, s / 2), s * .36, fill);
        final at = Offset(0, s * .05);
        canvas.drawPath(mikkyOutline(c + at, r * .7), hole);
        eyesIn(fill, at: at, scale: .7);
      case SmoothMark.dots:
        final outline = mikkyOutline(c, r);
        final eyes = mikkyEyes(c, r);
        final step = s * .055;
        for (var y = step / 2; y < s; y += step) {
          for (var x = step / 2; x < s; x += step) {
            final p = Offset(x, y);
            if (!outline.contains(p) || eyes.any((e) => _inOval(e.inflate(step * .35), p))) continue;
            canvas.drawCircle(p, step * .38, fill);
          }
        }
      case SmoothMark.line:
        canvas.drawPath(mikkyOutline(c, r), Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, s * .055)
          ..strokeJoin = StrokeJoin.round);
        eyesIn(fill);
    }
  }

  static bool _inOval(Rect o, Offset p) {
    final dx = (p.dx - o.center.dx) / (o.width / 2), dy = (p.dy - o.center.dy) / (o.height / 2);
    return dx * dx + dy * dy <= 1;
  }

  @override
  bool shouldRepaint(_SmoothPainter old) => old.mark != mark || old.dark != dark;
}

/// A smooth mark on black and on white, then small.
class SmoothSheet extends StatelessWidget {
  const SmoothSheet(this.mark, {super.key});

  final SmoothMark mark;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        SmoothTile(mark),
        const SizedBox(width: 10),
        SmoothTile(mark, dark: false),
      ]),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        for (final (px, dark) in const [(48.0, true), (32.0, false), (24.0, true), (16.0, true), (16.0, false)]) ...[
          Column(mainAxisSize: MainAxisSize.min, children: [
            SmoothTile(mark, size: px, dark: dark),
            const SizedBox(height: 4),
            Text('${px.round()}', style: uiText(TextSize.badge, color: ui.text3, tabular: true)),
          ]),
          const SizedBox(width: 10),
        ],
      ]),
    ]);
  }
}

/// A smooth mark beside his name, clean, in Geist: a signature.
class SmoothSignature extends StatelessWidget {
  const SmoothSignature(this.mark, {super.key, this.dark = true});

  final SmoothMark mark;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xFFFFFFFF) : const Color(0xFF0C0C0E);
    return Container(
      height: 96,
      padding: const EdgeInsets.fromLTRB(14, 0, 30, 0),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0C0C0E) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: dark ? null : Border.all(color: const Color(0x1F000000)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(dimension: 72, child: CustomPaint(painter: _SmoothPainter(mark, dark))),
        const SizedBox(width: 10),
        Text('mikky', style: TextStyle(fontFamily: 'Geist', fontSize: 40, fontWeight: FontWeight.w600, color: ink, height: 1, letterSpacing: -1.4)),
      ]),
    );
  }
}
