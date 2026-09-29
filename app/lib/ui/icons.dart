import 'package:flutter/widgets.dart';

/// The line icons of the prototypes (`composants.html`, `ux-a.html`): SVG
/// on a 24 × 24 grid, stroke 1.8, round caps and joins. Kept as SVG so
/// they can be compared with the prototypes and copied from them.
const _icons = <String, String>{
  'folder': '<path d="M3.5 7.5A1.5 1.5 0 0 1 5 6h4l2 2h8a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19 19H5a1.5 1.5 0 0 1-1.5-1.5z"/>',
  'sliders': '<path d="M4 7h9M17 7h3M4 12h3M11 12h9M4 17h11M19 17h1"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="17" r="2"/>',
  'up': '<path d="M12 19V5M6.5 10.5 12 5l5.5 5.5"/>',
  'go': '<path d="M5 12h14M13.5 6.5 19 12l-5.5 5.5"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'check': '<path d="m6 12.5 4 4 8-9"/>',
  'x': '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
  'right': '<path d="m9.5 6 6 6-6 6"/>',
  'left': '<path d="m14.5 6-6 6 6 6"/>',
  'down': '<path d="m6 9.5 6 6 6-6"/>',
  'search': '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
  'mail': '<rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="m4 7.5 8 5.5 8-5.5"/>',
  'share': '<path d="M12 14.5V4M7.5 8.5 12 4l4.5 4.5M5 12.5v5A2.5 2.5 0 0 0 7.5 20h9a2.5 2.5 0 0 0 2.5-2.5v-5"/>',
  'agents': '<rect x="3.5" y="5" width="17" height="14" rx="3.5"/><path d="m7.5 10 2.5 2-2.5 2M12.5 14.5h4"/>',
  'phone': '<rect x="7" y="3" width="10" height="18" rx="2.5"/><path d="M11 18h2"/>',
  'laptop': '<path d="M5.5 16V7A1.5 1.5 0 0 1 7 5.5h10A1.5 1.5 0 0 1 18.5 7v9M3 18.5h18"/>',
  'file': '<path d="M13.5 3.5H7A1.5 1.5 0 0 0 5.5 5v14A1.5 1.5 0 0 0 7 20.5h10a1.5 1.5 0 0 0 1.5-1.5V8.5z"/><path d="M13.5 3.5v5h5"/>',
  'refresh': '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4.5v4h-4"/>',
  'lock': '<rect x="5.5" y="11" width="13" height="9" rx="2"/><path d="M8.5 11V8.5a3.5 3.5 0 0 1 7 0V11"/>',
  'clip': '<path d="m19.5 11.5-7.8 7.8a4.6 4.6 0 0 1-6.5-6.5l8.1-8.1a3.1 3.1 0 0 1 4.4 4.4l-8.1 8.1a1.5 1.5 0 0 1-2.2-2.2l7.4-7.4"/>',
  'more': '<circle cx="6" cy="12" r="1.1"/><circle cx="12" cy="12" r="1.1"/><circle cx="18" cy="12" r="1.1"/>',
  'mic': '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
  'stop': '<rect x="7" y="7" width="10" height="10" rx="2"/>',
};

/// Names of every icon, for the kit.
Iterable<String> get iconNames => _icons.keys;

final Map<String, Path> _paths = {};

/// The icon [name] as a path on the 24 × 24 grid.
Path iconPath(String name) => _paths[name] ??= parseSvgShapes(_icons[name] ?? (throw ArgumentError('icon $name')));

/// A line icon, [size] px, in [color] (the text color by default).
class MikkyIcon extends StatelessWidget {
  const MikkyIcon(this.name, {super.key, this.size = 20, this.color, this.stroke = 1.8});

  final String name;
  final double size;
  final Color? color;

  /// Stroke width on the 24 px grid (the check of a done step: 3.2).
  final double stroke;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _IconPainter(iconPath(name), color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000), stroke),
  );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.path, this.color, this.stroke);

  final Path path;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.path != path || old.color != color || old.stroke != stroke;
}

/// Parses the few SVG shapes the icons use: `path` (M L H V C A Z, both
/// cases, implicit repeats), `circle` and `rect` (with `rx`).
Path parseSvgShapes(String svg) {
  final out = Path();
  for (final m in RegExp(r'<(path|circle|rect)\s([^>]*)/?>').allMatches(svg)) {
    final attrs = {for (final a in RegExp(r'([\w-]+)="([^"]*)"').allMatches(m[2]!)) a[1]!: a[2]!};
    double n(String k) => double.parse(attrs[k] ?? '0');
    switch (m[1]) {
      case 'circle':
        out.addOval(Rect.fromCircle(center: Offset(n('cx'), n('cy')), radius: n('r')));
      case 'rect':
        final rect = Rect.fromLTWH(n('x'), n('y'), n('width'), n('height'));
        out.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(n('rx'))));
      case 'path':
        _addPathData(out, attrs['d']!);
    }
  }
  return out;
}

void _addPathData(Path p, String d) {
  final tokens = RegExp(r'[MmLlHhVvCcAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?').allMatches(d).map((m) => m[0]!).toList();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double num() => double.parse(tokens[i++]);
  // Arc flags may be written stuck together ("0 0 1" or "011"): the
  // tokenizer splits "1.5" fine but not "01"; the icons never do that.
  while (i < tokens.length) {
    if (isCmd(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd == 'M') {
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = num() + (rel ? x : 0);
        y = num() + (rel ? y : 0);
        sx = x;
        sy = y;
        p.moveTo(x, y);
      case 'L':
        x = num() + (rel ? x : 0);
        y = num() + (rel ? y : 0);
        p.lineTo(x, y);
      case 'H':
        x = num() + (rel ? x : 0);
        p.lineTo(x, y);
      case 'V':
        y = num() + (rel ? y : 0);
        p.lineTo(x, y);
      case 'C':
        final x1 = num() + (rel ? x : 0), y1 = num() + (rel ? y : 0);
        final x2 = num() + (rel ? x : 0), y2 = num() + (rel ? y : 0);
        x = num() + (rel ? x : 0);
        y = num() + (rel ? y : 0);
        p.cubicTo(x1, y1, x2, y2, x, y);
      case 'A':
        final rx = num(), ry = num(), rot = num(), large = num() != 0, sweep = num() != 0;
        x = num() + (rel ? x : 0);
        y = num() + (rel ? y : 0);
        p.arcToPoint(Offset(x, y), radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
      case 'Z':
        p.close();
        x = sx;
        y = sy;
    }
  }
}
