import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion.dart';
import '../pixel_fx.dart';
import 'pixel_map.dart';

// Trials, shown on the design boards only: fireworks in the two signature
// colors (design.md §3 and §13).

/// The calm firework in the signature colors: its frames (small, middle,
/// big, middle), blue at the heart and orange at the tips.
class SignatureFirework extends StatelessWidget {
  const SignatureFirework({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) => Looping(
    period: const Duration(milliseconds: 3600),
    frozenAt: .3,
    builder: (context, t) {
      const frames = [0, 1, 2, 1];
      final frame = frames[(t * frames.length).floor() % frames.length];
      return CustomPaint(size: Size.square(size), painter: PixelMapPainter(_signatureFrame(frame), _colors));
    },
  );

  static final _frames = <int, List<String>>{};

  /// a–b the signature blue, o–q the orange.
  static final _colors = {
    'a': PixelFxPalette.signatureBlue.levels[0],
    'b': PixelFxPalette.signatureBlue.levels[1],
    'c': PixelFxPalette.signatureBlue.levels[2],
    'o': PixelFxPalette.signatureOrange.levels[0],
    'p': PixelFxPalette.signatureOrange.levels[1],
    'q': PixelFxPalette.signatureOrange.levels[2],
  };

  static List<String> _signatureFrame(int frame) => _frames.putIfAbsent(frame, () {
    const n = 7, c = 3;
    return [
      for (var y = 0; y < n; y++)
        [
          for (var x = 0; x < n; x++)
            switch (pixelLevel(CalmFirework.frame(frame, x - c, y - c))) {
              null => '.',
              // The heart and the first ring in blue, then the orange.
              _ when math.max((x - c).abs(), (y - c).abs()) == 0 => 'a',
              _ when math.max((x - c).abs(), (y - c).abs()) == 1 => (x == c || y == c) ? 'b' : 'c',
              _ when math.max((x - c).abs(), (y - c).abs()) == 2 => (x == c || y == c) ? 'q' : 'p',
              _ => 'o',
            },
        ].join(),
    ];
  });
}

/// Fireworks in the two signature colors, many shapes (user request,
/// 2026-09-30: « sois innovant, imagine des trucs »). Blue and orange
/// only; to try in the boards.
enum SignatureFxKind {
  /// A sphere that opens: orange heads, blue trails.
  peony,

  /// A blue burst, then an orange one further out.
  twoStage,

  /// Sparks that go out and droop, leaving blue trails.
  willow,

  /// A ring that widens, blue and orange in turns, turning.
  ring,

  /// Two arms turning, one blue, one orange.
  spiral,

  /// Four blue arms that split in two orange ones at their ends.
  crossette,

  /// The sparks land in the shape of Mikky's head, blink, and scatter.
  cat,

  /// Pixels twinkling here and there in a disk that breathes.
  glitter,

  /// A blue comet rises, bursts orange.
  comet,

  /// Square waves going out, blue then orange.
  waves,
}

class SignatureFx extends StatelessWidget {
  const SignatureFx(this.kind, {super.key, this.size = 72});

  final SignatureFxKind kind;
  final double size;

  static String nameOf(SignatureFxKind k) => switch (k) {
    SignatureFxKind.peony => 'Pivoine',
    SignatureFxKind.twoStage => 'Deux temps',
    SignatureFxKind.willow => 'Saule',
    SignatureFxKind.ring => 'Anneau',
    SignatureFxKind.spiral => 'Spirale',
    SignatureFxKind.crossette => 'Crossette',
    SignatureFxKind.cat => 'Mikky',
    SignatureFxKind.glitter => 'Paillettes',
    SignatureFxKind.comet => 'Comète',
    SignatureFxKind.waves => 'Ondes',
  };

  /// One loop, in seconds.
  static double periodOf(SignatureFxKind k) => switch (k) {
    SignatureFxKind.peony => 2.6,
    SignatureFxKind.twoStage => 3.0,
    SignatureFxKind.willow => 3.4,
    SignatureFxKind.ring => 2.4,
    SignatureFxKind.spiral => 4.0,
    SignatureFxKind.crossette => 2.8,
    SignatureFxKind.cat => 4.6,
    SignatureFxKind.glitter => 6.0,
    SignatureFxKind.comet => 2.8,
    SignatureFxKind.waves => 2.1,
  };

  /// Still (goldens, fewer animations): a moment where it shows well.
  static double _still(SignatureFxKind k) => switch (k) {
    SignatureFxKind.peony => .42,
    SignatureFxKind.twoStage => .6,
    SignatureFxKind.willow => .45,
    SignatureFxKind.ring => .4,
    SignatureFxKind.spiral => .2,
    SignatureFxKind.crossette => .72,
    SignatureFxKind.cat => .6,
    SignatureFxKind.glitter => .3,
    SignatureFxKind.comet => .62,
    SignatureFxKind.waves => .5,
  };

  @override
  Widget build(BuildContext context) {
    final period = periodOf(kind);
    return Looping(
      key: ValueKey(kind),
      period: Duration(milliseconds: (period * 1000).round()),
      frozenAt: _still(kind),
      builder: (context, t) => CustomPaint(size: Size.square(size), painter: _SignaturePainter(kind, t * period, period)),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.kind, this.t, this.period);

  final SignatureFxKind kind;

  /// Seconds into the loop.
  final double t;
  final double period;

  static const _n = 13;
  static const _c = 6.0;

  // The pixels: brightness and tone (0 blue, 1 orange).
  late final _i = List<double>.filled(_grid * _grid, 0);
  late final _tone = List<int>.filled(_grid * _grid, 0);

  int get _grid => kind == SignatureFxKind.cat ? 16 : _n;

  void _put(double x, double y, double i, int tone) {
    final xi = x.round(), yi = y.round();
    if (xi < 0 || yi < 0 || xi >= _grid || yi >= _grid || i <= 0) return;
    final k = yi * _grid + xi;
    if (i > _i[k]) {
      _i[k] = i;
      _tone[k] = tone;
    }
  }

  static double _out(double x) => 1 - math.pow(1 - x.clamp(0.0, 1.0), 3).toDouble();

  /// Goes out over the last part of the loop.
  static double _fade(double p, double from) => p < from ? 1 : (1 - (p - from) / (1 - from)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final p = (t / period) % 1;
    switch (kind) {
      case SignatureFxKind.peony:
        _peony(p);
      case SignatureFxKind.twoStage:
        _twoStage(p);
      case SignatureFxKind.willow:
        _willow(p);
      case SignatureFxKind.ring:
        _ring(p);
      case SignatureFxKind.spiral:
        _spiral();
      case SignatureFxKind.crossette:
        _crossette(p);
      case SignatureFxKind.cat:
        _cat(p);
      case SignatureFxKind.glitter:
        _glitter();
      case SignatureFxKind.comet:
        _comet(p);
      case SignatureFxKind.waves:
        _waves();
    }
    paintPixelGrid(canvas, size, _grid, (x, y) {
      final k = y * _grid + x;
      final level = pixelLevel(_i[k]);
      if (level == null) return null;
      return (_tone[k] == 0 ? PixelFxPalette.signatureBlue : PixelFxPalette.signatureOrange).levels[level];
    });
  }

  /// Sparks out from the middle: [count] directions, the head at [r],
  /// a trail of [trail] pixels behind in the other tone.
  void _burst(double r, int count, double i, {int head = 1, int trail = 3, double turn = 0, double cx = _c, double cy = _c}) {
    for (var k = 0; k < count; k++) {
      final a = turn + k * math.pi * 2 / count;
      final dx = math.cos(a), dy = math.sin(a);
      _put(cx + dx * r, cy + dy * r, i, head);
      for (var s = 1; s <= trail; s++) {
        final rr = r - s * .9;
        if (rr < .6) break;
        _put(cx + dx * rr, cy + dy * rr, i * (.78 - s * .16), 1 - head);
      }
    }
  }

  void _peony(double p) {
    final e = _out(p / .55);
    final f = _fade(p, .6);
    if (p < .2) _put(_c, _c, 1 - p * 2, 0);
    _burst(.6 + 5.2 * e, 16, f, trail: 2);
    // A second, inner shell, blue.
    if (p > .12) _burst(.4 + 2.6 * _out((p - .12) / .5), 8, f * .85, head: 0, trail: 0, turn: math.pi / 8);
  }

  void _twoStage(double p) {
    // First: blue, eight directions.
    if (p < .55) {
      final f1 = _fade(p / .55, .6);
      _put(_c, _c, f1, 0);
      _burst(.5 + 2.8 * _out(p / .35), 8, f1, head: 0, trail: 2);
    }
    // Then: orange, further out, sixteen.
    if (p > .35) {
      final q = (p - .35) / .65;
      _burst(3 + 3.2 * _out(q / .6), 16, _fade(q, .55), trail: 1, turn: math.pi / 16);
    }
  }

  void _willow(double p) {
    final tau = p * period;
    final f = _fade(p, .6);
    if (p < .1) _put(_c, _c - 1, 1, 0);
    for (var k = 0; k < 10; k++) {
      final a = -math.pi / 2 + (k - 4.5) * .62;
      Offset at(double s) {
        final d = 4.6 * (1 - math.exp(-2.4 * s));
        return Offset(_c + math.cos(a) * d, _c - 1 + math.sin(a) * d + .75 * s * s);
      }

      final h = at(tau);
      _put(h.dx, h.dy, f, 1);
      for (var s = 1; s <= 5; s++) {
        final back = tau - s * .13;
        if (back <= 0) break;
        final o = at(back);
        _put(o.dx, o.dy, f * (.8 - s * .11), 0);
      }
    }
  }

  void _ring(double p) {
    final r = .8 + 5.2 * _out(p / .7);
    final f = _fade(p, .55);
    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        final dx = x - _c, dy = y - _c;
        final d = math.sqrt(dx * dx + dy * dy);
        final on = 1 - (d - r).abs() / .7;
        if (on <= 0) continue;
        final sector = ((math.atan2(dy, dx) + math.pi) / (math.pi * 2) * 10 + t * 1.5).floor();
        _put(x.toDouble(), y.toDouble(), f * (.55 + .45 * on), sector.isEven ? 0 : 1);
      }
    }
    // What stays inside: a few blue embers.
    if (p > .3) _burst(r * .45, 6, f * .5, head: 0, trail: 0, turn: t);
  }

  void _spiral() {
    _put(_c, _c, 1, 0);
    for (var arm = 0; arm < 2; arm++) {
      // From the heart out, brighter at the tip, like a pinwheel.
      for (var s = 1; s <= 9; s++) {
        final rad = s * .62;
        final a = t * 1.9 + arm * math.pi + rad * .5;
        _put(_c + math.cos(a) * rad, _c + math.sin(a) * rad, .45 + s / 16, arm);
      }
    }
  }

  void _crossette(double p) {
    final f = _fade(p, .7);
    const reach = 3.2;
    final e1 = _out(p / .4);
    _put(_c, _c, p < .3 ? 1 : .5 * f, 0);
    for (var k = 0; k < 4; k++) {
      final a = k * math.pi / 2;
      final dx = math.cos(a), dy = math.sin(a);
      // The arm, blue.
      final r = .6 + (reach - .6) * e1;
      for (var s = 0; s < 4; s++) {
        final rr = r - s * .9;
        if (rr < .6) break;
        _put(_c + dx * rr, _c + dy * rr, (p < .4 ? 1 : f * .8) * (1 - s * .2), 0);
      }
      // At its end, two orange sparks, at 45° on each side.
      if (p > .38) {
        final e2 = _out((p - .38) / .4);
        for (final side in [-1, 1]) {
          final b = a + side * math.pi / 4;
          for (var s = 0; s < 3; s++) {
            final d = .7 + 2.6 * e2 - s * .85;
            if (d < .5) break;
            _put(_c + dx * reach + math.cos(b) * d, _c + dy * reach + math.sin(b) * d, f * (1 - s * .25), 1);
          }
        }
      }
    }
  }

  /// Mikky's head, as a line: its edge in orange, its eyes in blue.
  static final List<(int, int, int)> _catTargets = () {
    final rows = PixelMikky.head;
    bool k(int x, int y) => y >= 0 && y < rows.length && x >= 0 && x < rows[y].length && rows[y][x] != '.';
    return [
      for (var y = 0; y < rows.length; y++)
        for (var x = 0; x < rows[y].length; x++)
          if (rows[y][x] == 'w')
            (x, y, 0)
          else if (rows[y][x] == 'k' && (!k(x - 1, y) || !k(x + 1, y) || !k(x, y - 1) || !k(x, y + 1)))
            (x, y, 1),
    ];
  }();

  void _cat(double p) {
    const cx = 7.5, cy = 6.5;
    if (p < .14) {
      // The spark in the middle.
      _put(cx, cy, .4 + p / .14 * .6, 0);
      return;
    }
    for (final (i, (x, y, tone)) in _catTargets.indexed) {
      // Out from the middle to its place, the far ones a little later.
      final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      final q = _out((p - .14 - dist * .008) / .3);
      var px = cx + (x - cx) * q, py = cy + (y - cy) * q;
      var bright = 1.0;
      // A blink, the eyes only.
      if (tone == 0 && p > .6 && p < .64) continue;
      // Then it scatters: each pixel goes out on its own, falling.
      if (p > .78) {
        final s = (p - .78) / .22;
        if (pixelHash(i * 7 + 3) < s * 1.3) continue;
        py += s * s * 3 * pixelHash(i * 13);
        px += (x - cx) * s * .25;
        bright = 1 - s * .5;
      }
      _put(px, py, bright, tone);
    }
  }

  void _glitter() {
    final r = 4.3 + 1.4 * math.sin(t * math.pi * 2 / 6);
    _put(_c, _c, 1, 0);
    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        final dx = x - _c, dy = y - _c;
        if (math.sqrt(dx * dx + dy * dy) > r) continue;
        final id = y * _n + x;
        final v = math.sin((t / (.9 + pixelHash(id) * .8) + pixelHash(id * 3)) * math.pi * 2);
        if (v > .55) _put(x.toDouble(), y.toDouble(), .3 + (v - .55) / .45 * .7, pixelHash(id * 5) > .5 ? 1 : 0);
      }
    }
  }

  void _comet(double p) {
    if (p < .4) {
      // It rises, blue, a tail below.
      final y = (_n - 1) - (_n - 1 - _c + 1) * _out(p / .4);
      for (var s = 0; s < 4; s++) {
        _put(_c, y + s, 1 - s * .24, 0);
      }
      return;
    }
    final q = (p - .4) / .6;
    final f = _fade(q, .5);
    _put(_c, _c - 1, q < .2 ? 1 : 0, 0);
    _burst(.6 + 4.6 * _out(q / .6), 12, f, trail: 2, cy: _c - 1);
    // Sparks falling after.
    if (q > .45) {
      for (var k = 0; k < 6; k++) {
        final x = _c - 4 + k * 1.6, y = _c + 1 + (q - .45) * 8 + pixelHash(k) * 2;
        _put(x, y, f * .7, k.isEven ? 0 : 1);
      }
    }
  }

  void _waves() {
    const every = .7;
    final newest = (t / every).floor();
    for (var m = newest; m > newest - 4; m--) {
      final age = t - m * every;
      if (age < 0) continue;
      final r = age * 4.2;
      if (r > 7) continue;
      for (var y = 0; y < _n; y++) {
        for (var x = 0; x < _n; x++) {
          final d = math.max((x - _c).abs(), (y - _c).abs());
          // One pixel thick.
          final on = 1 - (d - r).abs() * 2.2;
          if (on > 0) _put(x.toDouble(), y.toDouble(), (.5 + on * .5) * (1 - r / 9), m.isEven ? 0 : 1);
        }
      }
    }
    _put(_c, _c, .9, 0);
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => old.t != t || old.kind != kind;
}
