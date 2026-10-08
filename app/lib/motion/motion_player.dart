import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import '../ui/buttons.dart';
import '../ui/motion.dart';
import '../ui/selectors.dart';
import '../ui/tokens.dart';

/// A [Choreography] to look at closely (2026-10-05, « qu'on regarde tout
/// ça ensemble »): its scene, a time bar to go to any instant (click or
/// drag), slow motion, play again, loop, its marks and the curves of some
/// of its tracks under the bar. Still at [poster] until played.
///
/// Light (2026-10-06, « la planche lag de fou »): it plays only when asked;
/// while it plays, only the scene and the playhead are drawn again, each
/// in its own layer; the bar, its marks and curves are drawn once.
class MotionPlayer extends StatefulWidget {
  const MotionPlayer({
    super.key,
    required this.choreography,
    required this.scene,
    this.width = 520,
    this.curves = const [],
    this.poster,
  });

  final Choreography choreography;

  /// The scene at [t] seconds.
  final Widget Function(BuildContext context, double t) scene;
  final double width;

  /// Tracks drawn under the time bar, each on its own scale.
  final List<String> curves;

  /// The instant shown still; default: 60 % of the way.
  final double? poster;

  @override
  State<MotionPlayer> createState() => _MotionPlayerState();
}

class _MotionPlayerState extends State<MotionPlayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);

  /// Where we are (seconds); the scene and the playhead follow it alone.
  late final ValueNotifier<double> _time = ValueNotifier(widget.poster ?? widget.choreography.duration * .6);
  bool _playing = false, _loop = true;
  double _speed = 1;
  Duration _last = Duration.zero;

  /// After the end, a short rest before playing again.
  static const _rest = .9;

  Choreography get _c => widget.choreography;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Motion.loops(context) && _playing) _stop();
  }

  void _play() {
    if (!Motion.loops(context)) return;
    if (_time.value >= _c.duration) _time.value = 0;
    _playing = true;
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _stop() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    var t = _time.value + math.min(dt, .1) * _speed;
    if (t >= _c.duration + (_loop ? _rest : 0)) {
      if (_loop) {
        t = 0;
      } else {
        t = _c.duration;
        setState(_stop);
      }
    }
    _time.value = t;
  }

  void _seek(double x) {
    if (_playing) setState(_stop);
    _time.value = (x / widget.width).clamp(0.0, 1.0) * _c.duration;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  static String _secs(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} s';

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final w = widget.width;
    // Narrow: fewer speeds, no loop switch (it loops), the time only.
    final narrow = w < 420;
    final barHeight = 30 + widget.curves.length * 16.0;
    return SizedBox(
      width: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ValueListenableBuilder<double>(
                valueListenable: _time,
                builder: (context, t, _) => widget.scene(context, math.min(t, _c.duration)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            RoundButton(_playing ? 'pause' : 'play', size: 30, onPressed: () => setState(() => _playing ? _stop() : _play()), tooltip: _playing ? 'Pause' : 'Lire'),
            const SizedBox(width: 6),
            RoundButton('refresh', size: 30, ghost: true, onPressed: () => setState(() {
              _time.value = 0;
              _play();
            }), tooltip: 'Rejouer'),
            const SizedBox(width: 10),
            for (final (label, s) in narrow ? const [('×0,25', .25), ('×1', 1.0)] : const [('×0,25', .25), ('×0,5', .5), ('×1', 1.0)]) ...[
              MChip(label, on: _speed == s, soft: _speed != s, onTap: () => setState(() => _speed = s)),
              const SizedBox(width: 4),
            ],
            if (!narrow) ...[
              const SizedBox(width: 6),
              MChip('Boucle', on: _loop, soft: !_loop, onTap: () => setState(() => _loop = !_loop)),
            ],
            const Spacer(),
            ValueListenableBuilder<double>(
              valueListenable: _time,
              builder: (context, t, _) {
                final at = _secs(math.min(t, _c.duration));
                return Text(narrow ? at : '$at / ${_secs(_c.duration)}', style: uiText(TextSize.label, color: ui.text2, tabular: true));
              },
            ),
          ]),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _seek(d.localPosition.dx),
            onHorizontalDragStart: (d) => _seek(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => _seek(d.localPosition.dx),
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(w, barHeight),
                // Drawn once: the bar, its marks, the curves.
                painter: _TimelinePainter(_c, widget.curves, ui),
                // Drawn again as time goes: the played part and the playhead.
                foregroundPainter: _PlayheadPainter(_c, _time, ui),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The time bar: its marks and their names, the curves of some tracks
/// under it. Nothing in it moves.
class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.c, this.curves, this.ui);

  final Choreography c;
  final List<String> curves;
  final MikkyUi ui;

  static const _colors = [Color(0xFF0A84FF), Color(0xFFFF9F0A), Color(0xFF30D158), Color(0xFFBF5AF2), Color(0xFFFF375F)];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    double x(double s) => s / c.duration * w;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 18, w, 4), const Radius.circular(2)), Paint()..color = ui.track);
    // The marks, their names above when there is room.
    var free = -1e9;
    for (final m in c.marks) {
      final mx = x(m.at);
      canvas.drawRect(Rect.fromLTWH(mx - .5, 15, 1, 10), Paint()..color = ui.text3);
      final p = TextPainter(text: TextSpan(text: m.name, style: uiText(10.5, color: ui.text3)), textDirection: TextDirection.ltr)..layout();
      final lx = (mx - p.width / 2).clamp(0.0, w - p.width);
      if (lx > free) {
        p.paint(canvas, Offset(lx, 0));
        free = lx + p.width + 6;
      }
      p.dispose();
    }
    // The curves, each on its own scale.
    for (var i = 0; i < curves.length; i++) {
      final name = curves[i];
      final top = 30.0 + i * 16, h = 12.0;
      const n = 160;
      final values = [for (var k = 0; k <= n; k++) c.value(name, c.duration * k / n)];
      final lo = values.reduce(math.min), hi = values.reduce(math.max);
      final span = hi - lo < 1e-9 ? 1.0 : hi - lo;
      final path = Path();
      for (var k = 0; k <= n; k++) {
        final px = w * k / n, py = top + h - (values[k] - lo) / span * h;
        k == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
      }
      final color = _colors[i % _colors.length];
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: .85));
      final p = TextPainter(text: TextSpan(text: name, style: uiText(9.5, color: color)), textDirection: TextDirection.ltr)..layout();
      p.paint(canvas, Offset(w - p.width, top - 1));
      p.dispose();
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.c != c || old.ui != ui || !listEquals(old.curves, curves);
}

/// What moves on the time bar: the part played, and where we are.
class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter(this.c, this.time, this.ui) : super(repaint: time);

  final Choreography c;
  final ValueListenable<double> time;
  final MikkyUi ui;

  @override
  void paint(Canvas canvas, Size size) {
    final x = math.min(time.value, c.duration) / c.duration * size.width;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 18, x, 4), const Radius.circular(2)), Paint()..color = ui.text2);
    canvas.drawRect(Rect.fromLTWH(x - .75, 12, 1.5, size.height - 12), Paint()..color = ui.text);
    canvas.drawCircle(Offset(x, 20), 5, Paint()..color = ui.text);
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) => old.c != c || old.time != time || old.ui != ui;
}
