import 'package:flutter/widgets.dart';

/// A CSS `box-shadow`, kept as written in `design/prototypes/mikky-ui.css`
/// so the values can be checked against it. [inset] shadows are drawn
/// inside the shape (Flutter has none of its own).
class CssShadow {
  const CssShadow(this.dx, this.dy, this.blur, this.color, {this.spread = 0, this.inset = false});

  final double dx, dy, blur, spread;
  final Color color;
  final bool inset;

  /// CSS blur radius is twice the Gaussian sigma.
  double get sigma => blur / 2;

  @override
  bool operator ==(Object other) =>
      other is CssShadow &&
      other.dx == dx &&
      other.dy == dy &&
      other.blur == blur &&
      other.spread == spread &&
      other.color == color &&
      other.inset == inset;

  @override
  int get hashCode => Object.hash(dx, dy, blur, spread, color, inset);
}

/// The UI tokens of the small window (`mikky-ui.css`, `.t-light` and
/// `.t-dark`), colors picked on `design/references/boutons-lanceur.png`.
class MikkyUi {
  const MikkyUi._({
    required this.isLight,
    required this.board,
    required this.island,
    required this.well,
    required this.raise,
    required this.track,
    required this.thumb,
    required this.ctlA,
    required this.ctlB,
    required this.ink,
    required this.inkHover,
    required this.onInk,
    required this.text,
    required this.text2,
    required this.text3,
    required this.line,
    required this.hover,
    required this.hl,
    required this.hlEdge,
    required this.knob,
    required this.shCtl,
    required this.shThumb,
    required this.shBar,
    required this.shInk,
    required this.inset,
    required this.islandShadow,
    required this.blue,
    required this.purple,
    required this.amber,
    required this.green,
    required this.red,
    required this.yellow,
    required this.grey,
  });

  static const light = MikkyUi._(
    isLight: true,
    board: Color(0xFFF9F8F9),
    island: Color(0xFFFFFFFF),
    well: Color(0xFFF4F3F5),
    raise: Color(0xD6F4F3F4),
    track: Color(0xFFE8E7E9),
    thumb: Color(0xFFFFFFFF),
    ctlA: Color(0xFFF1F0F2),
    ctlB: Color(0xFFE4E3E5),
    ink: Color(0xFF050406),
    inkHover: Color(0xFF232126),
    onInk: Color(0xFFFFFFFF),
    text: Color(0xFF111012),
    text2: Color(0xFF6E6D72),
    text3: Color(0xFFA2A1A6),
    line: Color(0x12000000),
    hover: Color(0x09000000),
    hl: Color(0xF2FFFFFF),
    hlEdge: Color(0xE6FFFFFF),
    knob: Color(0xFFFFFFFF),
    shCtl: [CssShadow(0, 1, 2, Color(0x14000000)), CssShadow(0, 3, 8, Color(0x0D000000))],
    shThumb: [CssShadow(0, 1, 2, Color(0x14000000)), CssShadow(0, 3, 10, Color(0x12000000))],
    shBar: [CssShadow(0, 10, 30, Color(0x1A141218)), CssShadow(0, 2, 6, Color(0x0F141218))],
    shInk: [CssShadow(0, 6, 16, Color(0x33050406)), CssShadow(0, 1, 2, Color(0x40050406))],
    inset: [CssShadow(0, 1, 2, Color(0x0F000000), inset: true)],
    islandShadow: [
      CssShadow(0, 0, 0, Color(0x14000000), spread: .5),
      CssShadow(0, 24, 60, Color(0x1F141218)),
      CssShadow(0, 4, 14, Color(0x0F141218)),
    ],
    blue: Color(0xFF007AFF),
    purple: Color(0xFFAF52DE),
    amber: Color(0xFFFF9500),
    green: Color(0xFF34C759),
    red: Color(0xFFFF3B30),
    yellow: Color(0xFFFFCC00),
    grey: Color(0xFFAEAEB2),
  );

  static const dark = MikkyUi._(
    isLight: false,
    board: Color(0xFF111113),
    island: Color(0xFF070708),
    well: Color(0xFF17171A),
    raise: Color(0xD618181B),
    track: Color(0xFF212125),
    thumb: Color(0xFF2C2C30),
    ctlA: Color(0xFF26262A),
    ctlB: Color(0xFF1B1B1E),
    ink: Color(0xFFF7F7F7),
    inkHover: Color(0xFFFFFFFF),
    onInk: Color(0xFF070708),
    text: Color(0xFFF5F5F7),
    text2: Color(0xFF8E8E93),
    text3: Color(0xFF66666C),
    line: Color(0x17FFFFFF),
    hover: Color(0x0AFFFFFF),
    hl: Color(0x12FFFFFF),
    hlEdge: Color(0x12FFFFFF),
    knob: Color(0xFFF7F7F7),
    shCtl: [CssShadow(0, 1, 2, Color(0x99000000)), CssShadow(0, 3, 8, Color(0x4D000000))],
    shThumb: [CssShadow(0, 1, 2, Color(0x80000000)), CssShadow(0, 3, 10, Color(0x66000000)), CssShadow(0, 1, 0, Color(0x0DFFFFFF), inset: true)],
    shBar: [CssShadow(0, 10, 30, Color(0x80000000)), CssShadow(0, 2, 6, Color(0x66000000))],
    shInk: [CssShadow(0, 6, 18, Color(0x80000000)), CssShadow(0, 1, 2, Color(0x80000000))],
    inset: [CssShadow(0, 1, 2, Color(0x80000000), inset: true)],
    islandShadow: [CssShadow(0, 0, 0, Color(0x14FFFFFF), spread: 1.3, inset: true), CssShadow(0, 24, 60, Color(0x99000000))],
    blue: Color(0xFF3B9EFF),
    purple: Color(0xFFA78BFA),
    amber: Color(0xFFF5A524),
    green: Color(0xFF34D399),
    red: Color(0xFFF4505E),
    yellow: Color(0xFFFB923C),
    grey: Color(0xFF5A5A5F),
  );

  final bool isLight;
  final Color board, island, well, raise, track, thumb, ctlA, ctlB, ink, inkHover, onInk;
  final Color text, text2, text3, line, hover, hl, hlEdge, knob;
  final List<CssShadow> shCtl, shThumb, shBar, shInk, inset, islandShadow;
  final Color blue, purple, amber, green, red, yellow, grey;

  /// Raised control: `linear-gradient(--ctl-a, --ctl-b)`.
  Gradient get control => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [ctlA, ctlB]);

  /// `inset 0 1px 0 var(--hl)`: the light edge on top of raised controls.
  CssShadow get highlight => CssShadow(0, 1, 0, hl, inset: true);

  /// `0 0 0 1.5px var(--ink)` + thumb shadow: a focused field.
  List<CssShadow> get focusRing => [CssShadow(0, 0, 0, ink, spread: 1.5), ...shThumb];

  static MikkyUi of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MikkyUiTheme>()?.ui ?? light;
}

/// Gives the UI tokens to what is below.
class MikkyUiTheme extends InheritedWidget {
  const MikkyUiTheme({super.key, required this.ui, required super.child});

  final MikkyUi ui;

  @override
  bool updateShouldNotify(MikkyUiTheme old) => old.ui != ui;
}

/// The fonts of the window. Geist and Geist Mono; the design boards
/// switch them to try others (user request, 2026-09-30).
abstract final class UiFonts {
  static String sans = 'Geist';
  static String mono = 'Geist Mono';
}

/// Text in the window's font ([UiFonts]), as the CSS sets it: [size] in
/// px, [tracking] in em.
TextStyle uiText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
  double height = 1.45,
  double tracking = 0,
  bool mono = false,
  bool tabular = false,
}) => TextStyle(
  fontFamily: mono ? UiFonts.mono : UiFonts.sans,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: tracking * size,
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  decoration: TextDecoration.none,
);
