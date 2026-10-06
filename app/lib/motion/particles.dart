import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/tokens.dart';

/// Particles on their own, to put wherever they fit later (2026-10-06,
/// « juste des particules qu'on pourra mettre »): each one a loop, drawn
/// as a function of time (nothing to update; any instant can be shown).
enum ParticleEffect {
  sparks('Étincelles', 'Une gerbe de pixels qui jaillit du centre et retombe : un pouvoir qui éclate.', Duration(milliseconds: 1800), Color(0xFFFF2D55)),
  ring('Anneau', 'Un anneau de points doux qui s’ouvre à plat : un atterrissage, une réponse prise.', Duration(milliseconds: 1600), Color(0xFF7FD8FF)),
  dust('Poussière magique', 'Des grains de lumière qui montent lentement et scintillent : un fond qui vit.', Duration(milliseconds: 6000), Color(0xFFFFD27A)),
  fireflies('Lucioles', 'Quelques lumières qui flottent au hasard et respirent : il réfléchit, il attend.', Duration(milliseconds: 8000), Color(0xFFB8FF6A)),
  confetti('Confettis', 'Des confettis en pixels lancés en l’air, qui retombent en tournant : une tâche finie.', Duration(milliseconds: 2600), Color(0xFFFF8A1F)),
  shooting('Étoiles filantes', 'Des traits de lumière qui traversent en biais, de temps en temps.', Duration(milliseconds: 4000), Color(0xFFE6E6FF)),
  pixels('Pixels qui montent', 'Des petits carrés qui montent et s’effacent, comme du calcul : il travaille.', Duration(milliseconds: 3000), Color(0xFF2E9BFF));

  const ParticleEffect(this.label, this.note, this.period, this.color);

  final String label, note;
  final Duration period;
  final Color color;
}

/// One [effect] at [t] seconds, on the island's background.
class ParticlesScene extends StatelessWidget {
  const ParticlesScene(this.effect, this.t, {super.key, this.size = const Size(260, 170)});

  final ParticleEffect effect;
  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: size.width,
      height: size.height,
      color: ui.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF070708),
      child: CustomPaint(painter: _ParticlesPainter(effect, t, ui.isLight)),
    );
  }
}

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter(this.effect, this.t, this.light);

  final ParticleEffect effect;
  final double t;
  final bool light;

  static final _sparks = Burst(
    seed: 21,
    count: 46,
    angleFrom: math.pi * 1.05,
    angleTo: math.pi * 1.95,
    speedMin: 70,
    speedMax: 190,
    sizeMin: 2,
    sizeMax: 3.5,
    lifeMin: .8,
    lifeMax: 1.4,
    drag: 1.4,
    gravity: 150,
  );
  static final _ring = Burst(seed: 11, count: 54, speedMin: 90, speedMax: 150, sizeMin: 1.6, sizeMax: 3, lifeMin: .8, lifeMax: 1.3, drag: 2.2, alphaMin: .5);
  static final _confetti = Burst(
    seed: 4,
    count: 40,
    angleFrom: math.pi * 1.2,
    angleTo: math.pi * 1.8,
    speedMin: 160,
    speedMax: 280,
    sizeMin: 3,
    sizeMax: 4.5,
    lifeMin: 1.8,
    lifeMax: 2.4,
    drag: 1.6,
    gravity: 190,
    alphaMin: .9,
  );

  /// Drawn once at random: (x 0..1, phase 0..1, speed, size, sway).
  static final _motes = () {
    final rng = math.Random(8);
    return [for (var i = 0; i < 34; i++) (rng.nextDouble(), rng.nextDouble(), .6 + .8 * rng.nextDouble(), 1 + 1.6 * rng.nextDouble(), rng.nextDouble() * 6)];
  }();

  static const _confettiColors = [Color(0xFFFF2D55), Color(0xFFFF8A1F), Color(0xFFFFD23F), Color(0xFF34E07A), Color(0xFF2E9BFF), Color(0xFFBF5AF2)];

  @override
  void paint(Canvas canvas, Size size) {
    final c = effect.color;
    final center = Offset(size.width / 2, size.height * .62);
    final paint = Paint()..isAntiAlias = true;
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    // On white, a light glow would vanish: a little deeper there.
    Color tone(Color color, double a) => (light ? Color.lerp(color, const Color(0xFF000000), .18)! : color).withValues(alpha: a.clamp(0.0, 1.0));
    final hot = Color.lerp(c, const Color(0xFFFFFFFF), .55)!;

    switch (effect) {
      case ParticleEffect.sparks:
        for (final s in _sparks.at(t)) {
          final o = center + Offset(s.x, s.y);
          final col = Color.lerp(hot, c, s.progress)!;
          glow.color = tone(c, s.alpha * .5);
          canvas.drawCircle(o, s.size * 1.4, glow);
          paint.color = tone(col, s.alpha);
          canvas.drawRect(Rect.fromCenter(center: Offset(o.dx.roundToDouble(), o.dy.roundToDouble()), width: s.size, height: s.size), paint);
        }
      case ParticleEffect.ring:
        for (final s in _ring.at(t)) {
          final o = center + Offset(s.x, s.y * .38);
          glow.color = tone(c, s.alpha * .6);
          canvas.drawCircle(o, s.size * 1.6, glow);
          paint.color = tone(hot, s.alpha);
          canvas.drawCircle(o, s.size / 2, paint);
        }
      case ParticleEffect.dust:
        for (final (x, phase, speed, sz, sway) in _motes) {
          // Up, again and again: each grain at its own place in the loop.
          final p = (t / 6 * speed + phase) % 1;
          final y = size.height * (1.05 - p * 1.1);
          final px = size.width * x + math.sin(t * .8 + sway) * 8;
          final twinkle = .55 + .45 * math.sin(t * 3 + sway * 2);
          final a = math.sin(p * math.pi) * twinkle;
          glow.color = tone(c, a * .55);
          canvas.drawCircle(Offset(px, y), sz * 2.2, glow);
          paint.color = tone(hot, a);
          canvas.drawCircle(Offset(px, y), sz * .6, paint);
        }
      case ParticleEffect.fireflies:
        for (final (x, phase, speed, sz, sway) in _motes.take(9)) {
          final a0 = t * .35 * speed + sway;
          final o = Offset(
            size.width * (.15 + .7 * x) + math.sin(a0) * 26 + math.sin(a0 * 2.3) * 8,
            size.height * (.2 + .6 * phase) + math.cos(a0 * 1.3) * 18,
          );
          final pulse = .5 + .5 * math.sin(t * 2.2 * speed + sway * 3);
          glow
            ..color = tone(c, .25 + .45 * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawCircle(o, 6 + sz * 2 * pulse, glow);
          paint.color = tone(hot, .5 + .5 * pulse);
          canvas.drawCircle(o, 1.6 + sz * .5, paint);
        }
      case ParticleEffect.confetti:
        final from = Offset(size.width / 2, size.height * .72);
        var i = 0;
        for (final s in _confetti.at(t)) {
          final o = from + Offset(s.x, s.y);
          final spin = t * (4 + i % 5) + i;
          canvas.save();
          canvas.translate(o.dx, o.dy);
          canvas.rotate(spin);
          // Flat confetti turning: they narrow as they spin.
          paint.color = tone(_confettiColors[i % _confettiColors.length], s.alpha);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s.size * (.35 + .65 * math.cos(spin * 1.7).abs()), height: s.size * 1.6), paint);
          canvas.restore();
          i++;
        }
      case ParticleEffect.shooting:
        for (var k = 0; k < 3; k++) {
          // Each star crosses in .7 s, at its own moment of the loop.
          final p = ((t / 4) + k * .37) % 1 / .18;
          if (p > 1) continue;
          final startX = size.width * (.2 + .25 * k), startY = size.height * (.08 + .12 * k);
          final head = Offset(startX + p * 180, startY + p * 90);
          final tail = head - const Offset(46, 23);
          final a = math.sin(p * math.pi);
          paint
            ..shader = LinearGradient(colors: [tone(c, 0), tone(hot, a)]).createShader(Rect.fromPoints(tail, head))
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(tail, head, paint);
          paint.shader = null;
          glow
            ..color = tone(c, a * .7)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
          canvas.drawCircle(head, 3.5, glow);
        }
      case ParticleEffect.pixels:
        for (final (x, phase, speed, sz, sway) in _motes) {
          final p = (t / 3 * speed + phase) % 1;
          // On a grid of 4 px, step by step: computing, not floating.
          final y = (size.height * (1 - p) / 4).floor() * 4.0;
          final px = (size.width * (.1 + .8 * x) / 4).floor() * 4.0;
          final a = (1 - p) * (sway > 3 ? 1 : .6);
          final big = sz > 2 ? 3.0 : 2.0;
          paint.color = tone(Color.lerp(c, hot, sway / 6)!, a);
          canvas.drawRect(Rect.fromLTWH(px, y, big, big), paint);
        }
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter old) => old.t != t || old.effect != effect || old.light != light;
}
