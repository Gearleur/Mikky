import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../mikky/mikky_painter.dart';
import '../theme.dart';
import '../ui/pixel_fx.dart';
import 'launch.dart' show poseAt;

/// Mikky swallows a file, like Kirby (2026-10-08, the user: « une bouche
/// à la Kirby et Mikky qui se déforme, devient plus gros pour avaler le
/// fichier » — the one time he has a mouth, to validate). A file comes
/// over him: he sees it, opens wide and puffs up, it is pulled in (pixel
/// streaks of air); dropped, it shrinks into his mouth, he shuts it, stays
/// full and round a moment, bounces on a spring and is himself again.
///
/// Every variant has the same marks: `survole` (his mouth open, the file
/// held: from there to `lâché` loops while the file hovers), `lâché` (the
/// file dropped), `avalé`, `plein`, `revient`.
///
/// Tracks, besides his [MikkyProp]s: `look` (he turns to the file), `y`
/// (a hop, in his radius), `happy`, `closed` (his eyes); the file's
/// `fileDist` (from his mouth, in his radius), `fileSway` (across),
/// `fileScale`, `fileTilt`, `fileStretch` (pulled toward his mouth),
/// `fileAlpha`; `suck`, how hard the air goes in.
abstract final class Swallows {
  static final all = [kirby, gulp, greedy];

  /// The one the app plays.
  static final inApp = kirby;

  /// Kirby's way: a wide mouth, puffed up while he inhales, full and round
  /// after, then a happy hop.
  static final kirby = Choreography(
    name: 'Kirby',
    duration: 2.8,
    marks: const [Mark(.1, 'il le voit'), Mark(.75, 'survole'), Mark(1.25, 'lâché'), Mark(1.45, 'avalé'), Mark(1.55, 'plein'), Mark(2.1, 'revient')],
    tracks: {
      'fileAlpha': const [Beat(0, 0), Beat(.15, 1, Easings.out), Beat(1.41, 1), Beat(1.47, 0, Easings.linear)],
      'fileDist': const [Beat(0, 3.4), Beat(.45, 1.9, Easings.out), Beat(.75, 1.55, Easings.inOut), Beat(1.25, 1.55), Beat(1.45, 0, Easings.inCubic)],
      'fileScale': const [Beat(0, 1), Beat(1.25, 1), Beat(1.45, .15, Easings.inCubic)],
      'fileStretch': const [Beat(.35, 0), Beat(.75, .22, Easings.out), Beat(1.25, .22), Beat(1.38, .9, Easings.inCubic), Beat(1.45, .2)],
      'fileTilt': [const Beat(0, .25), const Beat(.75, -.08, Easings.inOut), ...Choreography.wiggle(.75, 1.25, -.08, .1, 2), const Beat(1.45, .4, Easings.inCubic)],
      'fileSway': [const Beat(.75, 0), ...Choreography.wiggle(.75, 1.25, 0, .12, 3)],
      'suck': const [Beat(.35, 0), Beat(.65, 1, Easings.out), Beat(1.38, 1), Beat(1.48, 0, Easings.out)],
      'look': const [Beat(.1, 0), Beat(.4, 1, Easings.out), Beat(1.45, 1), Beat(1.7, 0, Easings.inOut)],
      'eyeScale': const [Beat(.1, 1), Beat(.25, 1.22, Easings.back), Beat(.45, 1.05, Easings.inOut)],
      'earLeft': [const Beat(.12, 0), Beat(.5, .45, Easings.spring(const SpringSpec(220, .45), .38)), const Beat(1.45, .45), const Beat(1.55, -.25, Easings.out), Beat(2.1, -.25), const Beat(2.18, .55, Easings.out), Beat(2.6, 0, Easings.spring(const SpringSpec(200, .4), .42))],
      'earRight': [const Beat(.16, 0), Beat(.54, .45, Easings.spring(const SpringSpec(220, .45), .38)), const Beat(1.47, .45), const Beat(1.57, -.25, Easings.out), Beat(2.12, -.25), const Beat(2.2, .55, Easings.out), Beat(2.62, 0, Easings.spring(const SpringSpec(200, .4), .42))],
      'mouth': [const Beat(.35, 0), Beat(.75, 1, Easings.spring(const SpringSpec(260, .5), .4)), ...Choreography.wiggle(.75, 1.25, 1, .06, 2), const Beat(1.42, 1.05), const Beat(1.5, 0, Easings.out)],
      'puff': [const Beat(.35, 0), const Beat(.75, .3, Easings.out), const Beat(1.45, .32), Beat(1.9, 1, Easings.spring(const SpringSpec(260, .38), .45)), const Beat(2.1, 1), Beat(2.65, 0, Easings.spring(const SpringSpec(220, .35), .55))],
      'open': const [Beat(.6, 1), Beat(.75, .8, Easings.out), Beat(1.25, .8), Beat(1.4, 1, Easings.out)],
      'scaleX': [const Beat(.35, 1), const Beat(.75, 1.04, Easings.out), const Beat(1.45, 1.04), const Beat(1.5, 1.12, Easings.out), Beat(1.9, 1, Easings.spring(const SpringSpec(240, .4), .4)), ...Choreography.wiggle(1.6, 2.0, 1, .04, 2), const Beat(2.1, 1), const Beat(2.16, 1.1, Easings.out), Beat(2.6, 1, Easings.spring(const SpringSpec(260, .4), .44))],
      'scaleY': [const Beat(.35, 1), const Beat(.75, 1.04, Easings.out), ...Choreography.wiggle(.75, 1.25, 1.04, .02, 2), const Beat(1.45, 1.04), const Beat(1.5, .9, Easings.out), Beat(1.9, 1, Easings.spring(const SpringSpec(240, .4), .4)), ...Choreography.wiggle(1.6, 2.0, 1, -.05, 2), const Beat(2.1, 1), const Beat(2.16, .86, Easings.out), Beat(2.6, 1, Easings.spring(const SpringSpec(260, .4), .44))],
      'y': const [Beat(2.16, 0), Beat(2.34, -.32, Easings.out), Beat(2.52, 0, Easings.inCubic)],
      'happy': const [Beat(1.5, 0), Beat(1.51, 1, Easings.linear), Beat(2.6, 1), Beat(2.61, 0, Easings.linear)],
    },
  );

  /// Quick: a smaller mouth, the file snapped in, one big puff and a
  /// satisfied « gloups ».
  static final gulp = Choreography(
    name: 'Gloups',
    duration: 1.9,
    marks: const [Mark(.08, 'il le voit'), Mark(.5, 'survole'), Mark(.9, 'lâché'), Mark(1.0, 'avalé'), Mark(1.05, 'plein'), Mark(1.25, 'revient')],
    tracks: {
      'fileAlpha': const [Beat(0, 0), Beat(.1, 1, Easings.out), Beat(.97, 1), Beat(1.01, 0, Easings.linear)],
      'fileDist': const [Beat(0, 3.2), Beat(.35, 1.7, Easings.out), Beat(.5, 1.6, Easings.inOut), Beat(.9, 1.6), Beat(1.0, 0, Easings.inCubic)],
      'fileScale': const [Beat(0, 1), Beat(.9, 1), Beat(1.0, .12, Easings.inCubic)],
      'fileStretch': const [Beat(.9, 0), Beat(.96, 1.1, Easings.inCubic), Beat(1.0, .2)],
      'fileTilt': [const Beat(0, .2), const Beat(.5, 0, Easings.out), ...Choreography.wiggle(.5, .9, 0, .08, 2)],
      'fileSway': [const Beat(.5, 0), ...Choreography.wiggle(.5, .9, 0, .08, 2)],
      'suck': const [Beat(.3, 0), Beat(.5, .7, Easings.out), Beat(.95, .7), Beat(1.02, 0, Easings.out)],
      'look': const [Beat(.08, 0), Beat(.3, 1, Easings.out), Beat(1.0, 1), Beat(1.2, 0, Easings.inOut)],
      'eyeScale': const [Beat(.08, 1), Beat(.2, 1.18, Easings.back), Beat(.4, 1, Easings.inOut)],
      'earLeft': [const Beat(.1, 0), Beat(.4, .35, Easings.spring(const SpringSpec(240, .45), .3)), const Beat(1.0, .35), const Beat(1.06, .6, Easings.out), Beat(1.5, 0, Easings.spring(const SpringSpec(200, .38), .44))],
      'earRight': [const Beat(.13, 0), Beat(.43, .35, Easings.spring(const SpringSpec(240, .45), .3)), const Beat(1.02, .35), const Beat(1.08, .6, Easings.out), Beat(1.52, 0, Easings.spring(const SpringSpec(200, .38), .44))],
      'mouth': [const Beat(.3, 0), Beat(.5, .8, Easings.spring(const SpringSpec(300, .55), .2)), const Beat(.9, .8), const Beat(.97, .9), const Beat(1.02, 0, Easings.out)],
      'puff': [const Beat(.3, 0), const Beat(.5, .15, Easings.out), const Beat(1.0, .15), Beat(1.25, .75, Easings.spring(const SpringSpec(320, .35), .25)), Beat(1.7, 0, Easings.spring(const SpringSpec(260, .32), .45))],
      'scaleX': [const Beat(1.0, 1), const Beat(1.04, 1.16, Easings.out), Beat(1.4, 1, Easings.spring(const SpringSpec(300, .38), .36))],
      'scaleY': [const Beat(1.0, 1), const Beat(1.04, .86, Easings.out), Beat(1.4, 1, Easings.spring(const SpringSpec(300, .38), .36))],
      'y': const [Beat(1.3, 0), Beat(1.42, -.18, Easings.out), Beat(1.55, 0, Easings.inCubic)],
      'happy': const [Beat(1.04, 0), Beat(1.05, 1, Easings.linear), Beat(1.8, 1), Beat(1.81, 0, Easings.linear)],
    },
  );

  /// Slower, greedy: he opens very wide and inflates a lot while he
  /// inhales, wobbles like jelly once full, then lets it all go.
  static final greedy = Choreography(
    name: 'Gourmand',
    duration: 3.5,
    marks: const [Mark(.15, 'il le voit'), Mark(1.0, 'survole'), Mark(1.6, 'lâché'), Mark(1.85, 'avalé'), Mark(1.95, 'plein'), Mark(2.75, 'revient')],
    tracks: {
      'fileAlpha': const [Beat(0, 0), Beat(.2, 1, Easings.out), Beat(1.8, 1), Beat(1.87, 0, Easings.linear)],
      'fileDist': const [Beat(0, 3.6), Beat(.6, 2.1, Easings.out), Beat(1.0, 1.7, Easings.inOut), Beat(1.6, 1.7), Beat(1.85, 0, Easings.inCubic)],
      'fileScale': const [Beat(0, 1), Beat(1.6, 1), Beat(1.85, .15, Easings.inCubic)],
      'fileStretch': const [Beat(.5, 0), Beat(1.0, .35, Easings.out), Beat(1.6, .35), Beat(1.76, 1, Easings.inCubic), Beat(1.85, .2)],
      'fileTilt': [const Beat(0, .3), const Beat(1.0, -.1, Easings.inOut), ...Choreography.wiggle(1.0, 1.6, -.1, .14, 3), const Beat(1.85, .5, Easings.inCubic)],
      'fileSway': [const Beat(1.0, 0), ...Choreography.wiggle(1.0, 1.6, 0, .16, 4)],
      'suck': const [Beat(.45, 0), Beat(.9, 1.3, Easings.out), Beat(1.78, 1.3), Beat(1.9, 0, Easings.out)],
      'look': const [Beat(.15, 0), Beat(.5, 1, Easings.out), Beat(1.85, 1), Beat(2.1, 0, Easings.inOut)],
      'eyeScale': const [Beat(.15, 1), Beat(.32, 1.25, Easings.back), Beat(.6, 1.08, Easings.inOut)],
      'earLeft': [const Beat(.15, 0), Beat(.6, .5, Easings.spring(const SpringSpec(200, .45), .45)), const Beat(1.85, .5), const Beat(1.95, -.35, Easings.out), Beat(2.75, -.35), const Beat(2.85, .6, Easings.out), Beat(3.3, 0, Easings.spring(const SpringSpec(180, .38), .45))],
      'earRight': [const Beat(.2, 0), Beat(.65, .5, Easings.spring(const SpringSpec(200, .45), .45)), const Beat(1.87, .5), const Beat(1.97, -.35, Easings.out), Beat(2.77, -.35), const Beat(2.87, .6, Easings.out), Beat(3.32, 0, Easings.spring(const SpringSpec(180, .38), .45))],
      'mouth': [const Beat(.45, 0), Beat(1.0, 1.15, Easings.spring(const SpringSpec(220, .5), .5)), ...Choreography.wiggle(1.0, 1.6, 1.15, .07, 3), const Beat(1.82, 1.2), const Beat(1.92, 0, Easings.out)],
      'puff': [const Beat(.45, 0), const Beat(1.0, .55, Easings.out), ...Choreography.wiggle(1.0, 1.6, .55, .04, 3), const Beat(1.85, .6), Beat(2.3, 1.25, Easings.spring(const SpringSpec(200, .32), .45)), const Beat(2.75, 1.25), Beat(3.35, 0, Easings.spring(const SpringSpec(200, .32), .6))],
      'open': const [Beat(.8, 1), Beat(1.0, .7, Easings.out), Beat(1.6, .7), Beat(1.8, 1, Easings.out)],
      'scaleX': [const Beat(1.85, 1), ...Choreography.wiggle(1.9, 2.7, 1, .09, 3), const Beat(2.75, 1), const Beat(2.82, 1.12, Easings.out), Beat(3.3, 1, Easings.spring(const SpringSpec(260, .4), .48))],
      'scaleY': [const Beat(1.85, 1), ...Choreography.wiggle(1.9, 2.7, 1, -.09, 3), const Beat(2.75, 1), const Beat(2.82, .85, Easings.out), Beat(3.3, 1, Easings.spring(const SpringSpec(260, .4), .48))],
      'y': const [Beat(2.85, 0), Beat(3.04, -.38, Easings.out), Beat(3.24, 0, Easings.inCubic)],
      'happy': const [Beat(1.95, 0), Beat(1.96, 1, Easings.linear), Beat(3.4, 1), Beat(3.41, 0, Easings.linear)],
      'sparkle': const [Beat(2.75, 0), Beat(2.85, 1, Easings.out), Beat(3.3, 0, Easings.inOut)],
    },
  );
}

/// Where the swallow is at the instant the app shows: while a file hovers,
/// up to `survole` then the loop until `lâché`; dropped, from `lâché` on;
/// the file gone without a drop, back from where it was, twice as fast.
double swallowTime(Choreography c, {required double hoverFor, double? droppedFor, double? leftFor, double? leftAt}) {
  final hold = c.at('survole') ?? c.duration * .3;
  final drop = c.at('lâché') ?? hold;
  if (droppedFor != null) return math.min(c.duration, drop + droppedFor);
  if (leftFor != null) return math.max(0, (leftAt ?? hold) - leftFor * 2);
  if (hoverFor <= hold || drop <= hold) return math.min(hoverFor, hold);
  return hold + (hoverFor - hold) % (drop - hold);
}

/// The swallow at [t]: Mikky on a white stage ([stage]) or on the island
/// (its theme), the file coming from [from] (a direction: the right on
/// the boards; from below at the top of the screen, from the left at its
/// right edge).
class SwallowScene extends StatelessWidget {
  const SwallowScene(this.choreography, this.t, {super.key, this.size = const Size(520, 220), this.radius = 34, this.from = const Offset(1, -.3)});

  final Choreography choreography;
  final double t;
  final Size size;
  final double radius;
  final Offset from;

  @override
  Widget build(BuildContext context) => CustomPaint(size: size, painter: SwallowPainter(choreography, t, radius, from: from));
}

class SwallowPainter extends CustomPainter {
  SwallowPainter(this.c, this.t, this.radius, {this.from = const Offset(1, -.3), this.stage = true, this.theme = MikkyTheme.light, this.name});

  final Choreography c;
  final double t;
  final double radius;
  final Offset from;
  final bool stage;
  final MikkyTheme theme;

  /// The file's name, small on its page (the app: what was dropped).
  final String? name;

  @override
  void paint(Canvas canvas, Size size) {
    if (stage) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFFFF), Color(0xFFF6F6F4)])
              .createShader(Offset.zero & size),
      );
    }
    final r = radius;
    final dir = from.distance == 0 ? const Offset(1, 0) : from / from.distance;
    // Mikky a little away from where the file comes.
    final center = Offset(size.width / 2 - dir.dx * r * .8, size.height * .56 - dir.dy * r * .35 + c.value('y', t) * r);

    final pose = poseAt(c, t);
    final look = c.value('look', t);
    pose[MikkyProp.yaw] = dir.dx * .45 * look;
    pose[MikkyProp.pitch] = -dir.dy * .3 * look;
    final eyes = c.value('happy', t) > .5
        ? EyeShape.happy
        : c.value('closed', t) > .5
            ? EyeShape.closed
            : EyeShape.oval;
    final g = MikkyGeometry.posed(pose, r, time: t, eyeLeft: eyes, eyeRight: eyes);
    MikkyPainter(
      geometry: g,
      center: center,
      rim: theme.mikkyRim,
      statusColor: theme.status,
      foreground: theme.foreground,
      showBadge: false,
    ).paint(canvas, size);

    // Where his mouth is (or would be), on screen.
    final m = g.mouth;
    final mouthLocal = m == null ? Offset(math.sin(pose.yaw) * r * .85, r * .3) : Offset(m.x, m.y);
    final mouth = center + Offset(g.translateX + mouthLocal.dx * g.scaleX, g.translateY + mouthLocal.dy * g.scaleY);

    _air(canvas, mouth, dir, r, c.value('suck', t));
    _file(canvas, mouth, dir, r);
    _sparkles(canvas, center, r, c.value('sparkle', t));
  }

  /// The air pulled into his mouth: short streaks of pixels from where the
  /// file is, speeding up as they get in.
  void _air(Canvas canvas, Offset mouth, Offset dir, double r, double suck) {
    if (suck <= .01) return;
    final px = (r * .08).roundToDouble().clamp(2.0, 4.0);
    final paint = Paint()..isAntiAlias = false;
    final color = theme.isLight ? const Color(0xFF8E8E93) : const Color(0xFFE5E5EA);
    const n = 16;
    for (var i = 0; i < n; i++) {
      final seed = i * 2.399963; // the golden angle: spread, never lined up
      final spread = (math.sin(seed * 3.1) * .8);
      final a = math.atan2(dir.dy, dir.dx) + spread;
      final speed = .9 + .5 * ((i * 7) % 5) / 4;
      final phase = (t * speed * 1.6 + i / n) % 1;
      // From far to the mouth, faster at the end (ease in).
      final d = r * (2.9 - 2.6 * phase * phase);
      final p = mouth + Offset(math.cos(a), math.sin(a)) * d;
      final alpha = suck.clamp(0.0, 1.0) * math.sin(phase * math.pi) * .75;
      if (alpha <= .02) continue;
      paint.color = color.withValues(alpha: alpha);
      // A streak: a few pixels along the way in.
      final steps = 1 + (phase * 3).floor();
      for (var k = 0; k < steps; k++) {
        final q = p + Offset(math.cos(a), math.sin(a)) * (k * px * 1.6);
        canvas.drawRect(Rect.fromLTWH((q.dx / px).roundToDouble() * px, (q.dy / px).roundToDouble() * px, px, px), paint);
      }
    }
  }

  /// The file: a page with a folded corner, a few lines, a colored tag;
  /// pulled toward his mouth (stretched along the way), shrinking in.
  void _file(Canvas canvas, Offset mouth, Offset dir, double r) {
    final alpha = c.value('fileAlpha', t);
    if (alpha <= .01) return;
    final dist = c.value('fileDist', t) * r;
    final sway = c.value('fileSway', t) * r;
    final across = Offset(-dir.dy, dir.dx);
    final at = mouth + dir * dist + across * sway;
    final scale = c.value('fileScale', t, 1);
    final stretch = c.value('fileStretch', t);
    final tilt = c.value('fileTilt', t);
    final w = r * .82 * scale, h = r * 1.04 * scale;
    final toMouth = math.atan2(-dir.dy, -dir.dx);

    canvas.save();
    canvas.translate(at.dx, at.dy);
    // Stretched along the way to his mouth.
    canvas.rotate(toMouth);
    canvas.scale(1 + stretch, 1 / (1 + stretch * .45));
    canvas.rotate(-toMouth + tilt);
    final page = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final fold = w * .3;
    final shape = Path()
      ..moveTo(page.left + w * .12, page.top)
      ..lineTo(page.right - fold, page.top)
      ..lineTo(page.right, page.top + fold)
      ..lineTo(page.right, page.bottom - w * .12)
      ..quadraticBezierTo(page.right, page.bottom, page.right - w * .12, page.bottom)
      ..lineTo(page.left + w * .12, page.bottom)
      ..quadraticBezierTo(page.left, page.bottom, page.left, page.bottom - w * .12)
      ..lineTo(page.left, page.top + w * .12)
      ..quadraticBezierTo(page.left, page.top, page.left + w * .12, page.top)
      ..close();
    canvas.drawShadow(shape, const Color(0xFF000000).withValues(alpha: .4 * alpha), r * .08, false);
    canvas.drawPath(shape, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha));
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, r * .025)
        ..color = const Color(0xFFD1D1D6).withValues(alpha: alpha),
    );
    // The folded corner.
    canvas.drawPath(
      Path()
        ..moveTo(page.right - fold, page.top)
        ..lineTo(page.right - fold, page.top + fold * .8)
        ..quadraticBezierTo(page.right - fold, page.top + fold, page.right - fold * .8, page.top + fold)
        ..lineTo(page.right, page.top + fold)
        ..close(),
      Paint()..color = const Color(0xFFE5E5EA).withValues(alpha: alpha),
    );
    // Its lines, and a tag in our blue.
    final line = Paint()
      ..color = const Color(0xFFC7C7CC).withValues(alpha: alpha)
      ..strokeWidth = math.max(1, h * .045)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = page.top + h * (.42 + i * .13);
      canvas.drawLine(Offset(page.left + w * .18, y), Offset(page.right - w * (i == 3 ? .42 : .18), y), line);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(page.left + w * .18, page.top + h * .14, w * .34, h * .14), Radius.circular(h * .04)),
      Paint()..color = PixelFxPalette.signatureBlue.levels[1].withValues(alpha: alpha),
    );
    canvas.restore();
  }

  /// A few pixel stars around him once he is himself again (the greedy
  /// one).
  void _sparkles(Canvas canvas, Offset center, double r, double amount) {
    if (amount <= .01) return;
    final paint = Paint()..isAntiAlias = false;
    final px = (r * .08).roundToDouble().clamp(2.0, 4.0);
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + (i - 2) * .55;
      final p = center + Offset(math.cos(a), math.sin(a)) * r * (1.45 + .25 * amount);
      paint.color = PixelFxPalette.signatureOrange.levels[i % 3].withValues(alpha: amount);
      for (final o in const [Offset(0, 0), Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
        canvas.drawRect(Rect.fromLTWH((p.dx / px).roundToDouble() * px + o.dx * px, (p.dy / px).roundToDouble() * px + o.dy * px, px, px), paint);
      }
    }
  }

  @override
  bool shouldRepaint(SwallowPainter old) => old.t != t || old.c != c || old.radius != radius || old.from != from || old.stage != stage || old.theme != theme;
}
