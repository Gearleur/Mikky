import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../foundation/motion.dart';
import '../foundation/status.dart';
import '../foundation/tokens.dart';
import 'pixel_fx.dart';

/// One star of a [StatusStack]; [key] follows it when the pile changes.
typedef StackStar = ({Object key, UiStatus status});

/// Agents' states piled up (2026-10-12, a trial for the closed island at
/// the top; user: « les étoiles peuvent se superposer avec un numéro s'il
/// y en a vraiment plein », then « les étoiles au milieu… le numéro à
/// droite des étoiles »): their stars ([StatusFx]) overlap, centered in
/// their place, the front one on the left and on top; each one cuts a
/// pixel's margin out of the ones behind it, so they read apart. Past
/// [shown], their number goes where its place wants it ([StackNumber]). A
/// star that comes dissolves in by
/// pixels, one that goes dissolves out (never a fade), the others slide to
/// their place; each star keeps its own beat, so they do not blink together.
class StatusStack extends StatefulWidget {
  const StatusStack({super.key, required this.stars, this.size = 18, this.step = 13, this.shown = 3});

  /// The front one first; only the first [shown] are drawn.
  final List<StackStar> stars;

  final double size;

  /// From one star to the next.
  final double step;
  final int shown;

  /// The width of [count] stars piled up.
  static double pileWidth(int count, {double size = 18, double step = 13}) =>
      count <= 0 ? 0 : size + step * (count - 1);

  @override
  State<StatusStack> createState() => _StatusStackState();
}

class _Entry {
  _Entry(this.status, this.slot, double x, this.phase, {required double now, required this.shownAt})
    : from = x,
      to = x,
      movedAt = now;

  UiStatus status;

  /// 0: the front one.
  int slot;

  /// Where it slides from and to, since [movedAt].
  double from, to, movedAt;

  /// Dissolving in since; null: there.
  double? shownAt;

  /// Dissolving out since.
  double? goneAt;

  /// Seconds into its effect: its own beat.
  final double phase;
}

class _StatusStackState extends State<StatusStack> with SingleTickerProviderStateMixin {
  static const _enter = .28, _leave = .22, _slide = .38;

  /// Its own time, in seconds: it runs only while something moves.
  double _now = 0, _base = 0;
  late final Ticker _ticker = createTicker((elapsed) => setState(() => _now = _base + elapsed.inMicroseconds / 1e6));
  final _entries = <Object, _Entry>{};
  var _born = 0;

  double get _area => StatusStack.pileWidth(widget.shown, size: widget.size, step: widget.step);

  @override
  void initState() {
    super.initState();
    _sync(appear: false);
  }

  @override
  void didUpdateWidget(StatusStack old) {
    super.didUpdateWidget(old);
    _sync(appear: !Motion.reduced(context));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Every star of the widget gets its place, the pile centered; the
  /// others go. It ticks only when something moves: rebuilt as is (the
  /// island redraws often), it stays still.
  void _sync({required bool appear}) {
    final now = _now;
    var moves = false;
    final w = widget;
    final wanted = w.stars.take(w.shown).toList();
    final start = (_area - StatusStack.pileWidth(wanted.length, size: w.size, step: w.step)) / 2;
    final keys = {for (final s in wanted) s.key};
    for (final e in _entries.entries) {
      if (!keys.contains(e.key) && e.value.goneAt == null) {
        e.value.goneAt = appear ? now : now - _leave;
        moves = true;
      }
    }
    for (var i = 0; i < wanted.length; i++) {
      final s = wanted[i], x = start + i * w.step;
      final e = _entries[s.key];
      if (e == null) {
        // Beats a third of the way apart (the firework: 3.6 s there and back).
        _entries[s.key] = _Entry(s.status, i, x, (_born++ * 1.2) % 3.6, now: now, shownAt: appear ? now : null);
        moves = true;
        continue;
      }
      e
        ..status = s.status
        ..slot = i;
      if (e.goneAt != null) {
        e.goneAt = null;
        e.shownAt = appear ? now : null;
        moves = true;
      }
      if (e.to != x) {
        e
          ..from = appear ? _xAt(e, now) : x
          ..to = x
          ..movedAt = now;
        moves = true;
      }
    }
    if (appear && moves && !_ticker.isActive) {
      _base = _now;
      _ticker.start();
    }
  }

  double _xAt(_Entry e, double now) {
    final k = ((now - e.movedAt) / _slide).clamp(0.0, 1.0);
    return e.from + (e.to - e.from) * Motion.enter.transform(k);
  }

  /// 0 to 1: how much of it is drawn.
  double _presence(_Entry e, double now) {
    final gone = e.goneAt, shown = e.shownAt;
    if (gone != null) return 1 - ((now - gone) / _leave).clamp(0.0, 1.0);
    if (shown != null) return ((now - shown) / _enter).clamp(0.0, 1.0);
    return 1;
  }

  bool _moving(_Entry e, double now) =>
      now - e.movedAt < _slide || (e.goneAt != null) || (e.shownAt != null && now - e.shownAt! < _enter);

  @override
  Widget build(BuildContext context) {
    final now = _now;
    _entries.removeWhere((_, e) => e.goneAt != null && now - e.goneAt! >= _leave);
    if (_ticker.isActive && !_entries.values.any((e) => _moving(e, now))) {
      // The last frame of a move: nothing more to tick for.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ticker.isActive) _ticker.stop();
      });
    }
    final ui = MikkyUi.of(context);
    final w = widget, area = _area;
    // The back ones first, the front one last: on top.
    final drawn = [for (final e in _entries.values) (x: _xAt(e, now), entry: e, presence: _presence(e, now))]
      ..sort((a, b) => b.entry.slot.compareTo(a.entry.slot));
    return SizedBox(
      width: area,
      height: w.size,
      child: Looping(
        period: const Duration(seconds: 24),
        frozenAt: .03,
        builder: (context, t) => CustomPaint(
          painter: _StackPainter([
            for (final d in drawn)
              _Drawn(
                x: d.x,
                status: d.entry.status,
                palette: PixelFxPalette.of(d.entry.status, ui).on(ui),
                t: d.entry.status == UiStatus.finished
                    ? StatusFx.effectOf(d.entry.status).still
                    : t * 24 / StatusFx.slowOf(d.entry.status) + d.entry.phase,
                presence: d.presence,
              ),
          ], w.size),
        ),
      ),
    );
  }
}

/// How many stars a [StatusStack] stands for when there are too many to
/// draw (null: none to say): small and grey, it fades in and out, keeping
/// its last number while it goes.
class StackNumber extends StatefulWidget {
  const StackNumber(this.number, {super.key});

  final int? number;

  @override
  State<StackNumber> createState() => _StackNumberState();
}

class _StackNumberState extends State<StackNumber> {
  late int? _last = widget.number;

  @override
  Widget build(BuildContext context) {
    _last = widget.number ?? _last;
    return AnimatedOpacity(
      opacity: widget.number == null ? 0 : 1,
      duration: Motion.of(context, Motion.fade),
      child: Text(
        '${_last ?? ''}',
        style: uiText(TextSize.caption, color: MikkyUi.of(context).text2, mono: true, height: 1, tabular: true),
      ),
    );
  }
}

class _Drawn {
  const _Drawn({required this.x, required this.status, required this.palette, required this.t, required this.presence});

  final double x;
  final UiStatus status;
  final PixelFxPalette palette;
  final double t, presence;

  PixelEffect get effect => StatusFx.effectOf(status);

  @override
  bool operator ==(Object other) =>
      other is _Drawn &&
      other.x == x &&
      other.status == status &&
      other.palette == palette &&
      other.t == t &&
      other.presence == presence;

  @override
  int get hashCode => Object.hash(x, status, palette, t, presence);
}

/// The stars from the back to the front, each one clearing what it shows,
/// one pixel wider, out of those behind (in a layer of their own: the
/// island shows through the gap). The bite follows its frame: a small star
/// barely touches the one behind, a big one pushes into it.
class _StackPainter extends CustomPainter {
  _StackPainter(this.stars, this.size);

  final List<_Drawn> stars;
  final double size;

  @override
  void paint(Canvas canvas, Size area) {
    if (stars.isEmpty) return;
    canvas.saveLayer((Offset.zero & area).inflate(size / 4), Paint());
    final clear = Paint()..blendMode = BlendMode.clear;
    final paint = Paint();
    for (final s in stars) {
      if (s.presence <= 0) continue;
      final n = s.effect.grid, c = n ~/ 2;
      final space = size * .018, cell = (size - space * (n - 1)) / n, pitch = cell + space;
      // Dissolving: a pixel is there once the dither lets it.
      bool kept(int x, int y) => s.presence >= 1 || pixelDither(x + 1, y + 1) < s.presence;
      final lit = <(int, int), Color>{
        for (var y = 0; y < n; y++)
          for (var x = 0; x < n; x++)
            if (pixelLevel(s.effect.at(s.t, x - c, y - c)) case final level? when kept(x, y))
              (x, y): s.palette.levels[level],
      };
      final margin = {
        for (final (x, y) in lit.keys) ...[(x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)],
      };
      for (final (x, y) in margin) {
        canvas.drawRect(Rect.fromLTWH(s.x + x * pitch - space / 2, y * pitch - space / 2, pitch, pitch), clear);
      }
      for (final MapEntry(key: (x, y), value: color) in lit.entries) {
        paint.color = color;
        canvas.drawRect(Rect.fromLTWH(s.x + x * pitch, y * pitch, cell, cell), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StackPainter old) => old.size != size || !_same(old.stars, stars);

  static bool _same(List<_Drawn> a, List<_Drawn> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
