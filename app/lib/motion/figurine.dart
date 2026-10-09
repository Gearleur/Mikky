import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/motion.dart';
import '../ui/pixel_fx.dart';
import '../ui/tokens.dart';

/// Mikky as a designer toy, after Pop Mart's Hirono (2026-10-08, the user:
/// « un style Hirono Pop Mart, plus physique, pour Mikky fatigué avec un
/// pyjama et un oreiller » — an exploration, to look at). A figurine on a
/// product shot: his real head in matte black vinyl with a soft shine,
/// heavy sleepy lids, pink cheeks and freckles; a fabric pyjama with its
/// hood, a print and sleeves too long (no hands, no feet, still him); a
/// pillow. He breathes slowly and nods off now and then.
enum FigurinePrint { stars, moons, clouds }

enum FigurineHood {
  /// A plain hood, a pillow on top hiding his ears.
  plain,

  /// His own ears out through two holes.
  earHoles,

  /// A hood with fabric cat ears over his.
  catEars,
}

enum FigurineHold { starPlush, pillow, nothing }

class FigurineLook {
  const FigurineLook({
    required this.name,
    required this.note,
    required this.fabric,
    required this.fabricDark,
    required this.print,
    required this.hood,
    required this.hold,
    this.pillowOnHead = false,
    this.cushion = false,
    this.eyesOpen = .4,
    this.sleeping = false,
  });

  final String name, note;

  /// The pyjama, lit and in its shadow.
  final Color fabric, fabricDark;
  final FigurinePrint print;
  final FigurineHood hood;
  final FigurineHold hold;
  final bool pillowOnHead;

  /// Sitting on a big cushion.
  final bool cushion;

  /// How open his eyes are under the heavy lids (0: shut).
  final double eyesOpen;

  /// Asleep: pixel « z » rising.
  final bool sleeping;
}

abstract final class FigurineLooks {
  static const all = [pillowHat, earsOut, catHood];

  static const pillowHat = FigurineLook(
    name: 'L’oreiller sur la tête',
    note: 'Au plus près de ton image : pyjama lilas à étoiles, capuche, un oreiller posé sur la tête qui cache ses oreilles, une petite étoile en peluche serrée dans ses manches. Les paupières lourdes, il pique du nez.',
    fabric: Color(0xFFB4B3E6),
    fabricDark: Color(0xFF8584C4),
    print: FigurinePrint.stars,
    hood: FigurineHood.plain,
    hold: FigurineHold.starPlush,
    pillowOnHead: true,
    eyesOpen: .42,
  );

  static const earsOut = FigurineLook(
    name: 'Les oreilles qui dépassent',
    note: 'Pyjama bleu nuit à lunes, ses oreilles noires sorties par deux trous de la capuche ; il serre un petit oreiller contre lui. Les yeux presque fermés.',
    fabric: Color(0xFF5E6BA8),
    fabricDark: Color(0xFF3E4980),
    print: FigurinePrint.moons,
    hood: FigurineHood.earHoles,
    hold: FigurineHold.pillow,
    eyesOpen: .2,
  );

  static const catHood = FigurineLook(
    name: 'La capuche de chat',
    note: 'Pyjama pêche à nuages, une capuche à oreilles de chat par-dessus les siennes ; il dort assis sur un gros coussin, des « z » en pixels montent.',
    fabric: Color(0xFFF4B9A2),
    fabricDark: Color(0xFFD98E77),
    print: FigurinePrint.clouds,
    hood: FigurineHood.catEars,
    hold: FigurineHold.nothing,
    cushion: true,
    eyesOpen: 0,
    sleeping: true,
  );
}

/// [look] on its product shot, alive (breath, nods) at 60 images a second
/// while it shows; still when Windows asks for fewer animations and in the
/// test pictures.
class FigurineLive extends StatefulWidget {
  const FigurineLive(this.look, {super.key, this.size = const Size(300, 360), this.frozenAt = 1.0});

  final FigurineLook look;
  final Size size;

  /// Seconds into its life where it stands still.
  final double frozenAt;

  @override
  State<FigurineLive> createState() => _FigurineLiveState();
}

class _FigurineLiveState extends State<FigurineLive> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => _t.value = widget.frozenAt + elapsed.inMicroseconds / 1e6);
  late final ValueNotifier<double> _t = ValueNotifier(widget.frozenAt);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = Motion.loops(context);
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
      _t.value = widget.frozenAt;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(size: widget.size, painter: FigurinePainter(widget.look, _t, dark: !MikkyUi.of(context).isLight)),
      );
}

class FigurinePainter extends CustomPainter {
  FigurinePainter(this.look, this.time, {this.dark = false}) : super(repaint: time);

  final FigurineLook look;
  final ValueListenable<double> time;
  final bool dark;

  static const _vinyl = Color(0xFF0C0C0E);
  static const _cream = Color(0xFFF4EFE2);
  static const _creamDark = Color(0xFFD9D1BE);

  @override
  void paint(Canvas canvas, Size size) {
    final l = look;
    final t = time.value;
    // His slow breath, and now and then a nod: his head drops, his eyes
    // close a little more, then he catches himself.
    final breath = math.sin(t * 2 * math.pi / 3.2);
    final n = (t % 6.5 - 4.6) / 1.4;
    final nod = n > 0 && n < 1 ? math.pow(math.sin(n * math.pi), 2).toDouble() : 0.0;
    final lag = math.sin((t - .35) * 2 * math.pi / 3.2);

    _backdrop(canvas, size);

    final w = size.width;
    final floor = size.height * .9;
    final cx = w / 2;
    const r = 66.0;
    final g = MikkyGeometry.posed(MikkyPose()..[MikkyProp.pitch] = -.06 - .08 * nod, r, eyeLeft: EyeShape.oval, eyeRight: EyeShape.oval);
    var hw = 0.0, top = 0.0, bottom = 0.0;
    for (var i = 0; i < g.pointCount; i++) {
      hw = math.max(hw, g.contour[i * 2].abs());
      top = math.min(top, g.contour[i * 2 + 1]);
      bottom = math.max(bottom, g.contour[i * 2 + 1]);
    }
    final hh = bottom;
    final seat = l.cushion ? 26.0 : 0.0;
    final head = Offset(cx, floor - seat - 150 + 1.6 * breath + 5 * nod);
    final shoulders = head.dy + hh * .72;

    // Shadow on the floor, under him and his cushion.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, floor + 2), width: hw * (l.cushion ? 2.9 : 2.4), height: 22),
      Paint()
        ..color = Color(0xFF000000).withValues(alpha: dark ? .5 : .2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    if (l.cushion) _cushion(canvas, Offset(cx, floor - 13), hw * 2.7, 34);

    final hoodOuter = Rect.fromCenter(center: head.translate(0, 6), width: hw * 2.42, height: hh * 2.5);
    final bodyFloor = floor - seat;

    // The hood behind his head, falling on his back.
    _fabric(canvas, Path()..addOval(hoodOuter), l.fabricDark, Color.lerp(l.fabricDark, const Color(0xFF000000), .25)!);

    // His body in the pyjama: sitting, his knees up in front.
    final torso = Path()
      ..moveTo(cx - hw * .7, shoulders)
      ..cubicTo(cx - hw * 1.02, shoulders + 30, cx - hw * 1.1, bodyFloor - 26, cx - hw * .9, bodyFloor - 4)
      ..quadraticBezierTo(cx, bodyFloor + 6, cx + hw * .9, bodyFloor - 4)
      ..cubicTo(cx + hw * 1.1, bodyFloor - 26, cx + hw * 1.02, shoulders + 30, cx + hw * .7, shoulders)
      ..close();
    _fabric(canvas, torso, l.fabric, l.fabricDark, print: true, breath: breath);
    for (final side in const [-1.0, 1.0]) {
      final knee = Path()..addOval(Rect.fromCenter(center: Offset(cx + side * hw * .5, bodyFloor - 15), width: hw * .95, height: 38));
      _fabric(canvas, knee, l.fabric, l.fabricDark, print: true, breath: breath, seed: side > 0 ? 7 : 3);
    }

    // His head: matte vinyl, the shadow under his chin on the pyjama first.
    canvas.drawOval(
      Rect.fromCenter(center: head.translate(0, hh * .86), width: hw * 1.5, height: 24),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(.03 * nod);
    final skull = Path()..addPolygon([for (var i = 0; i < g.pointCount; i++) Offset(g.contour[i * 2], g.contour[i * 2 + 1])], true);
    // His head without the ears; under a cat hood, the hood's ears are his.
    final dome = Path()..addOval(Rect.fromCenter(center: Offset.zero, width: hw * 2, height: hh * 2));
    final shown = l.hood == FigurineHood.catEars ? Path.combine(PathOperation.intersect, skull, dome) : skull;
    _vinylHead(canvas, shown, hw, top, hh);
    _face(canvas, g, l.eyesOpen * (1 - .7 * nod) * (.96 + .04 * breath), hw, hh);
    canvas.restore();

    // The hood's rim around his face, over his head.
    final face = Rect.fromCenter(center: head.translate(0, hh * .14), width: hw * 1.7, height: hh * 1.72);
    final rim = Path.combine(PathOperation.difference, Path()..addOval(hoodOuter), Path()..addOval(face));
    final holes = l.hood == FigurineHood.earHoles;
    if (holes) {
      // His own ears come out: the hood keeps away from them.
      final ears = Path.combine(
        PathOperation.intersect,
        Path.combine(PathOperation.difference, skull, Path()..addOval(Rect.fromCenter(center: Offset.zero, width: hw * 1.9, height: hh * 1.9))),
        Path()..addRect(Rect.fromLTRB(-hw * 2, top - 10, hw * 2, -hh * .55)),
      );
      final cut = Path.combine(PathOperation.difference, rim, ears.shift(head));
      _fabric(canvas, cut, l.fabric, l.fabricDark, print: true, seed: 11, breath: breath);
      _edgeShade(canvas, ears.shift(head));
    } else {
      _fabric(canvas, rim, l.fabric, l.fabricDark, print: true, seed: 11, breath: breath);
    }
    // The hood's hem, a soft fold around his face.
    canvas.drawOval(
      face.inflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Color.lerp(l.fabricDark, const Color(0xFF000000), .2)!.withValues(alpha: .45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    if (l.hood == FigurineHood.catEars) _hoodEars(canvas, hoodOuter, l);

    // Sleeves too long, meeting in front, and what he holds.
    final hug = Offset(cx, bodyFloor - 50 + 1.2 * breath);
    if (l.hold == FigurineHold.pillow) _smallPillow(canvas, hug.translate(0, -6), lag);
    for (final side in const [-1.0, 1.0]) {
      _sleeve(canvas, Offset(cx + side * hw * .74, shoulders + 12), hug.translate(side * (l.hold == FigurineHold.nothing ? 10 : 22), 6), l, side);
    }
    if (l.hold == FigurineHold.starPlush) _starPlush(canvas, hug.translate(0, -4), lag);

    if (l.pillowOnHead) _pillowHat(canvas, Offset(head.dx - 3, hoodOuter.top + 6 + 1.5 * lag + 3 * nod), hw * 2.55, 50, lag, l);
    if (l.sleeping) _zs(canvas, head.translate(hw * .9, -hh * 1.1), t);
  }

  void _backdrop(Canvas canvas, Size size) {
    final horizon = size.height * .66;
    final wall = Rect.fromLTWH(0, 0, size.width, horizon);
    final ground = Rect.fromLTRB(0, horizon, size.width, size.height);
    canvas.drawRect(
      wall,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Color(0xFF1C1C20), Color(0xFF26262B)] : const [Color(0xFFE9E6E1), Color(0xFFDEDAD4)],
        ).createShader(wall),
    );
    canvas.drawRect(
      ground,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Color(0xFF2E2E34), Color(0xFF232328)] : const [Color(0xFFF6F4F0), Color(0xFFEDEAE5)],
        ).createShader(ground),
    );
    // Light from the window on the left.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.9, -.7),
          radius: 1.2,
          colors: [Color(0xFFFFFFFF).withValues(alpha: dark ? .05 : .35), const Color(0x00FFFFFF)],
        ).createShader(Offset.zero & size),
    );
  }

  /// Fabric: its color, lit from the top left, shaded at the bottom right,
  /// with its print.
  void _fabric(Canvas canvas, Path path, Color base, Color shade, {bool print = false, double breath = 0, int seed = 0}) {
    final b = path.getBounds();
    canvas.drawPath(path, Paint()..color = base);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      b,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.45, -.55),
          radius: 1.15,
          colors: [const Color(0xFFFFFFFF).withValues(alpha: .28), base.withValues(alpha: 0), shade.withValues(alpha: .85)],
          stops: const [0, .45, 1],
        ).createShader(b),
    );
    if (print) _print(canvas, b, seed);
    // Soft occlusion all along its edge.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = shade.withValues(alpha: .5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.restore();
  }

  void _print(Canvas canvas, Rect b, int seed) {
    final paint = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .82);
    const step = 26.0;
    var i = seed;
    for (var y = b.top + 8; y < b.bottom; y += step) {
      for (var x = b.left + ((y / step).floor().isEven ? 6 : 19); x < b.right; x += step) {
        i++;
        final jitter = Offset(math.sin(i * 12.9898) * 4, math.cos(i * 78.233) * 4);
        final c = Offset(x, y) + jitter;
        final turn = i * .7;
        switch (look.print) {
          case FigurinePrint.stars:
            canvas.drawPath(_star(c, 5.2, 2.3, turn), paint);
          case FigurinePrint.moons:
            canvas.drawPath(
              Path.combine(PathOperation.difference, Path()..addOval(Rect.fromCircle(center: c, radius: 4.6)), Path()..addOval(Rect.fromCircle(center: c.translate(2.4, -1.6), radius: 4))),
              paint,
            );
          case FigurinePrint.clouds:
            final cloud = Path()
              ..addOval(Rect.fromCircle(center: c, radius: 3.6))
              ..addOval(Rect.fromCircle(center: c.translate(-4, 1.4), radius: 2.6))
              ..addOval(Rect.fromCircle(center: c.translate(4, 1.4), radius: 2.8));
            canvas.drawPath(cloud, paint);
        }
      }
    }
  }

  Path _star(Offset c, double outer, double inner, double turn) {
    final p = Path();
    for (var k = 0; k < 10; k++) {
      final a = -math.pi / 2 + turn + k * math.pi / 5;
      final rad = k.isEven ? outer : inner;
      final q = c + Offset(math.cos(a), math.sin(a)) * rad;
      k == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
    }
    return p..close();
  }

  /// His head in matte black vinyl: a soft light on the top left, a deeper
  /// black at the bottom, a satin shine, a faint light along the far edge.
  void _vinylHead(Canvas canvas, Path skull, double hw, double top, double hh) {
    final b = Rect.fromLTRB(-hw, top, hw, hh);
    canvas.drawPath(skull, Paint()..color = _vinyl);
    canvas.save();
    canvas.clipPath(skull);
    canvas.drawRect(
      b,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.4, -.45),
          radius: .95,
          colors: [Color(0xFF3B3B42), Color(0xFF16161A), Color(0xFF050506)],
          stops: [0, .5, 1],
        ).createShader(b),
    );
    // Satin shine, blurred, on the forehead.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-hw * .38, -hh * .5), width: hw * .7, height: hh * .34),
      Paint()
        ..color = const Color(0x2EFFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, hw * .08),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-hw * .46, -hh * .55), width: hw * .18, height: hh * .08),
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, hw * .02),
    );
    // Light bouncing from the pyjama on his lower right edge.
    canvas.drawPath(
      skull,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hw * .1
        ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x26E6E0FF)], stops: [0, .6, 1])
            .createShader(b)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, hw * .05),
    );
    canvas.restore();
  }

  /// His sleepy face: white eyes under heavy lids, tired shadows under
  /// them, pink cheeks with freckles (no mouth, ever).
  void _face(Canvas canvas, MikkyGeometry g, double open, double hw, double hh) {
    for (final e in g.eyes) {
      final w = e.width * e.scaleX * 1.08, h = e.fullHeight * e.scaleY;
      final c = Offset(e.x, e.y + h * .08);
      final eye = Rect.fromCenter(center: c, width: w, height: h);
      // Tired: a soft dark-grey shadow under each eye.
      canvas.drawOval(
        Rect.fromCenter(center: c.translate(0, h * .52), width: w * 1.3, height: h * .3),
        Paint()
          ..color = const Color(0x44686878)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      if (open >= .05) {
        final oval = Path()..addOval(eye);
        canvas.drawPath(
          oval,
          Paint()
            ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE4E4EC), Color(0xFFFFFFFF)]).createShader(eye),
        );
        canvas.save();
        canvas.clipPath(oval);
        // The heavy lid, its edge a little curved, a fine light on it.
        final lidY = eye.top + h * (1 - open.clamp(0.0, 1.0)) * .96;
        final lid = Path()
          ..moveTo(eye.left - 2, eye.top - 2)
          ..lineTo(eye.right + 2, eye.top - 2)
          ..lineTo(eye.right + 2, lidY + h * .06)
          ..quadraticBezierTo(c.dx, lidY - h * .1, eye.left - 2, lidY + h * .06)
          ..close();
        canvas.drawPath(
          lid,
          Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1A1A1F), Color(0xFF2A2A31)]).createShader(eye),
        );
        canvas.drawPath(
          Path()
            ..moveTo(eye.left, lidY + h * .06)
            ..quadraticBezierTo(c.dx, lidY - h * .1, eye.right, lidY + h * .06),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0x553A3A44),
        );
        canvas.restore();
      }
      if (open < .05) {
        // Shut: a soft curved line.
        canvas.drawPath(
          Path()
            ..moveTo(eye.left + w * .05, c.dy + h * .1)
            ..quadraticBezierTo(c.dx, c.dy + h * .32, eye.right - w * .05, c.dy + h * .1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFEDEDF2),
        );
      }
      // The lid's crease, just above the eye (none when they are shut).
      if (open >= .05) {
        canvas.drawArc(
          eye.inflate(2.5).translate(0, -1),
          math.pi * 1.15,
          math.pi * .7,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = const Color(0x40B8B8C8),
        );
      }
      // His cheek: a pink blush and four freckles.
      final cheek = c.translate(e.side * w * .55, h * .9);
      canvas.drawOval(
        Rect.fromCenter(center: cheek, width: w * 1.5, height: h * .5),
        Paint()
          ..color = const Color(0x88FF7F9A)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      final dot = Paint()..color = const Color(0xCCFFB59E);
      for (var k = 0; k < 4; k++) {
        canvas.drawCircle(cheek.translate((k - 1.5) * w * .2, (k.isEven ? -1 : 1) * h * .07), 1.3, dot);
      }
    }
  }

  void _edgeShade(Canvas canvas, Path ears) {
    canvas.save();
    canvas.clipPath(ears);
    canvas.drawPath(
      ears,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0x22FFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.restore();
  }

  void _hoodEars(Canvas canvas, Rect hood, FigurineLook l) {
    for (final side in const [-1.0, 1.0]) {
      final base = Offset(hood.center.dx + side * hood.width * .27, hood.top + hood.height * .1);
      final ear = Path()
        ..moveTo(base.dx - side * hood.width * .17, base.dy + 6)
        ..quadraticBezierTo(base.dx - side * 2, base.dy - 46, base.dx + side * hood.width * .14, base.dy - 34)
        ..quadraticBezierTo(base.dx + side * hood.width * .2, base.dy - 8, base.dx + side * hood.width * .12, base.dy + 14)
        ..close();
      _fabric(canvas, ear, l.fabric, l.fabricDark, seed: side > 0 ? 21 : 17);
      final inner = Path()
        ..moveTo(base.dx - side * hood.width * .08, base.dy + 2)
        ..quadraticBezierTo(base.dx + side * 2, base.dy - 32, base.dx + side * hood.width * .1, base.dy - 24)
        ..quadraticBezierTo(base.dx + side * hood.width * .13, base.dy - 6, base.dx + side * hood.width * .07, base.dy + 6)
        ..close();
      canvas.drawPath(inner, Paint()..color = const Color(0xFFFFD9D0));
    }
  }

  void _sleeve(Canvas canvas, Offset from, Offset to, FigurineLook l, double side) {
    final mid = Offset(from.dx + side * 10, (from.dy + to.dy) / 2 + 6);
    final arm = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);
    final b = arm.getBounds().inflate(20);
    // The sleeve, a soft tube of fabric, shaded underneath.
    canvas.drawPath(
      arm,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 30
        ..strokeCap = StrokeCap.round
        ..color = l.fabricDark.withValues(alpha: .6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      arm,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 27
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(l.fabric, const Color(0xFFFFFFFF), .2)!, l.fabric, l.fabricDark]).createShader(b),
    );
    // The cuff, a band at its end.
    canvas.drawCircle(to, 13.5, Paint()..color = Color.lerp(l.fabricDark, l.fabric, .35)!);
    canvas.drawCircle(to.translate(-side * 2, -2), 10, Paint()..color = l.fabric.withValues(alpha: .6));
  }

  void _starPlush(Canvas canvas, Offset c, double lag) {
    final star = _star(c, 22, 12, .05 * lag);
    canvas.drawPath(
      star,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFE8B23A),
    );
    final b = star.getBounds();
    canvas.drawPath(
      star,
      Paint()
        ..shader = const RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFFFE58A), Color(0xFFF5C24A)]).createShader(b),
    );
    final eyes = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF5A3A10);
    for (final s in const [-1.0, 1.0]) {
      canvas.drawArc(Rect.fromCenter(center: c.translate(s * 5, 1), width: 5, height: 4), 0, math.pi, false, eyes);
    }
  }

  void _smallPillow(Canvas canvas, Offset c, double lag) {
    final path = _cushionPath(c, 64, 48, .04 * lag);
    _cushionShade(canvas, path, const Color(0xFFF2F4FB), const Color(0xFFC9CEE4));
  }

  void _cushion(Canvas canvas, Offset c, double w, double h) {
    final path = _cushionPath(c, w, h, 0);
    _cushionShade(canvas, path, _cream, _creamDark);
  }

  /// A puffy cushion: four pinched corners, its edges bulging out.
  Path _cushionPath(Offset c, double w, double h, double turn) {
    final hw = w / 2, hh = h / 2;
    final p = Path()
      ..moveTo(-hw, -hh)
      ..quadraticBezierTo(0, -hh * 1.5, hw, -hh)
      ..quadraticBezierTo(hw * 1.12, 0, hw, hh)
      ..quadraticBezierTo(0, hh * 1.5, -hw, hh)
      ..quadraticBezierTo(-hw * 1.12, 0, -hw, -hh)
      ..close();
    return p.transform((Matrix4.identity()
          ..translateByDouble(c.dx, c.dy, 0, 1)
          ..rotateZ(turn))
        .storage);
  }

  void _cushionShade(Canvas canvas, Path path, Color base, Color shade) {
    final b = path.getBounds();
    canvas.drawPath(path.shift(const Offset(0, 3)), Paint()..color = const Color(0x22000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(path, Paint()..color = base);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      b,
      Paint()
        ..shader = RadialGradient(center: const Alignment(-.3, -.5), radius: 1.1, colors: [const Color(0xFFFFFFFF), base.withValues(alpha: 0), shade], stops: const [0, .5, 1])
            .createShader(b),
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = shade,
    );
  }

  /// The pillow on his head: draped over it, its corners hanging down,
  /// two lines of piping along it.
  void _pillowHat(Canvas canvas, Offset c, double w, double h, double lag, FigurineLook l) {
    final hw = w / 2;
    final droop = 16 + 2 * lag;
    final path = Path()
      ..moveTo(c.dx - hw, c.dy + droop * .3)
      ..quadraticBezierTo(c.dx, c.dy - h * 1.15, c.dx + hw, c.dy + droop * .3)
      ..quadraticBezierTo(c.dx + hw * 1.08, c.dy + droop * .8, c.dx + hw * .96, c.dy + droop + 10)
      ..quadraticBezierTo(c.dx, c.dy - 6, c.dx - hw * .96, c.dy + droop + 10)
      ..quadraticBezierTo(c.dx - hw * 1.08, c.dy + droop * .8, c.dx - hw, c.dy + droop * .3)
      ..close();
    // Its shadow on the hood.
    canvas.drawPath(path.shift(const Offset(2, 6)), Paint()..color = const Color(0x33000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    _cushionShade(canvas, path, _cream, _creamDark);
    canvas.save();
    canvas.clipPath(path);
    final piping = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = l.fabricDark.withValues(alpha: .75);
    for (final dy in const [14.0, 22.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - hw, c.dy + droop * .3 + dy)
          ..quadraticBezierTo(c.dx, c.dy - h * 1.15 + dy, c.dx + hw, c.dy + droop * .3 + dy),
        piping,
      );
    }
    canvas.restore();
  }

  /// « z » in pixels rising from him, one after the other.
  void _zs(Canvas canvas, Offset from, double t) {
    const px = 3.0;
    final paint = Paint()..isAntiAlias = false;
    final levels = PixelFxPalette.signatureBlue.levels;
    for (var k = 0; k < 3; k++) {
      final f = (t / 3 + k / 3) % 1;
      final alpha = math.sin(f * math.pi);
      final at = from.translate(f * 18 + k * 2, -f * 40);
      final size = (2 + k).toDouble();
      paint.color = (dark ? levels[0] : levels[1]).withValues(alpha: alpha);
      // A pixel « z »: top bar, diagonal, bottom bar.
      final n = size.toInt() + 2;
      for (var i = 0; i < n; i++) {
        canvas.drawRect(Rect.fromLTWH(at.dx + i * px, at.dy, px, px), paint);
        canvas.drawRect(Rect.fromLTWH(at.dx + i * px, at.dy + (n - 1) * px, px, px), paint);
        canvas.drawRect(Rect.fromLTWH(at.dx + (n - 1 - i) * px, at.dy + i * px, px, px), paint);
      }
    }
  }

  @override
  bool shouldRepaint(FigurinePainter old) => old.look != look || old.time != time || old.dark != dark;
}
