import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

/// Where the home lives: the wide island at the top, or the tall one at
/// the right edge.
enum HomePlacement { top, right }

/// The home's measures in one placement: the window, its
/// bar, its pages of tiles and where Mikky sits. Set for the island's real
/// sizes, not scaled from the mockups.
class HomeLayout {
  const HomeLayout._({
    required this.placement,
    required this.size,
    required this.columns,
    required this.rows,
    required this.tile,
    required this.tileWidth,
    required this.gap,
    required this.rowGap,
    required this.gridTop,
    required this.barTop,
    required this.bar,
    required this.foot,
    required this.side,
    required this.mikky,
    required this.mikkyAt,
    double? mikkyIdle,
    Offset? mikkyIdleAt,
    this.notch = false,
    this.stacked = false,
    int? idleColumns,
  }) : mikkyIdle = mikkyIdle ?? mikky,
       mikkyIdleAt = mikkyIdleAt ?? mikkyAt,
       idleColumns = idleColumns ?? columns;

  /// The notch at the right in [size]: its head (bar, Mikky 96 and the task
  /// side by side), then [columns] × [rows] wide tiles, [tileWidth] × 42,
  /// between the arrows, [gridGap] under the task.
  const HomeLayout._rightNotch({
    required Size size,
    required double tileWidth,
    required int columns,
    required int rows,
    double gridGap = 10,
  }) : this._(
         placement: HomePlacement.right,
         size: size,
         columns: columns,
         rows: rows,
         tile: 42,
         tileWidth: tileWidth,
         gap: 8,
         rowGap: 8,
         gridTop: taskTop + taskHeight + gridGap,
         barTop: 10,
         bar: 32,
         foot: 8,
         side: 12,
         mikky: 96,
         mikkyAt: const Offset(10, taskTop + (taskHeight - 96) / 2),
         notch: true,
         stacked: true,
       );

  /// Top: the notch (user, 2026-10-05, « Côte à côte »), 700 × 200 (760 ×
  /// 216 was « trop grand »). On the left, Mikky (96) and the latest task
  /// at work beside him, reaching to the apps (« la partie de gauche plus
  /// étendue »); nothing at work, Mikky alone, bigger (120). On the right,
  /// the other apps as wide tiles, 160 × 42, two by two (three columns
  /// when nothing is at work), arrows on each side when there are more.
  /// Quiet controls: a 32 px bar, a small foot.
  static const top = HomeLayout._(
    placement: HomePlacement.top,
    size: Size(700, 200),
    columns: 2,
    rows: 2,
    tile: 42,
    tileWidth: 160,
    gap: 8,
    rowGap: 8,
    gridTop: taskTop + (taskHeight - 2 * 42 - 8) / 2,
    barTop: 10,
    bar: 32,
    foot: 8,
    side: 12,
    mikky: 96,
    mikkyAt: Offset(10, taskTop + (taskHeight - 96) / 2),
    mikkyIdle: 120,
    mikkyIdleAt: Offset(10, 40),
    notch: true,
    idleColumns: 3,
  );

  /// Right, in the app: the notch of the top, upright, or the home of
  /// 2026-10-02 (`IslandMetrics.rightNotch`, the one switch for both).
  static const right = IslandMetrics.rightNotch ? rightNotch : rightTiles;

  /// Right: the notch of the top upright (2026-10-08, « transformer le
  /// notch du haut en notch de droite »; to validate with the user),
  /// 320 × 416. The top's own parts, laid out as a phone app, never
  /// turned: the same bar, then Mikky (96) and the task he looks at side
  /// by side exactly as at the top (the task 194 wide, the top's 190);
  /// under them, the other apps in one column of wide tiles, 248 × 42,
  /// four a page, the arrows on each side; the dots behind them, the
  /// same small foot. Nothing at work: Mikky sleeps in his place (the
  /// island keeps him there), the apps do not move.
  static const rightNotch = HomeLayout._rightNotch(
    size: Size(320, 416),
    tileWidth: 320 - 2 * 8 - 2 * arrowRoom,
    columns: 1,
    rows: 4,
  );

  /// A trial of the notch at the right (boards « Notch Right »): the same
  /// head, the apps two by two under it, 140 × 42 (120 cut « Nouvelle
  /// tâche »), six a page; wider and shorter, 360 × 366.
  static const rightTwoColumns = HomeLayout._rightNotch(
    size: Size(360, 366),
    tileWidth: (360 - 2 * 8 - 2 * arrowRoom - 8) / 2,
    columns: 2,
    rows: 3,
  );

  /// A trial of the notch at the right (boards « Notch Right »): as big as
  /// an agent's page, 344 × 520, so the island keeps its size from the
  /// home to a page; six apps a page in one column, 272 × 42.
  static const rightPage = HomeLayout._rightNotch(
    size: Size(344, 520),
    tileWidth: 344 - 2 * 8 - 2 * arrowRoom,
    columns: 1,
    rows: 6,
    gridGap: 14,
  );

  /// Right until 2026-10-08: the home of 2026-10-02 upright (« une version
  /// verticale de la version haut »): 64 px tiles, four rows of two — 8 a
  /// page — so 290 × 408: the bar, 10, the tiles, 10, the foot.
  static const rightTiles = HomeLayout._(
    placement: HomePlacement.right,
    size: Size(290, 408),
    columns: 2,
    rows: 4,
    tile: 64,
    tileWidth: 64,
    gap: 16,
    rowGap: 10,
    gridTop: 12 + 44 + 10,
    barTop: 12,
    bar: 44,
    foot: 10,
    side: 12,
    mikky: 72,
    mikkyAt: Offset(4, -4),
  );

  /// The task Mikky looks at, in the notch (top and right alike): from
  /// the bar's foot, this high.
  static const taskTop = 46.0, taskHeight = 120.0;

  /// A question takes the focus size and Mikky's focus position.
  static Size get questionSize => Size(IslandMetrics.top.focus.width, IslandMetrics.top.focus.height);
  static const questionPadding = EdgeInsets.fromLTRB(104, 16, 18, 12);
  static Offset get questionMikkyAt =>
      Offset(IslandMetrics.top.mikkyOpen.x - top.mikky / 2, IslandMetrics.top.mikkyOpen.y - top.mikky * .54);

  /// The task, this far from Mikky; at the top it reaches to [taskEnd]
  /// from the apps' area (190 wide), at the right to the side's margin.
  static const taskGap = 8.0, taskEnd = 4.0;

  /// The notch's page arrows (22) and their room beside the apps (6 px
  /// from them).
  static const arrow = 22.0, arrowRoom = arrow + 6;

  final HomePlacement placement;
  final Size size;

  /// The notch's look (the top since 2026-10-05, the right since
  /// 2026-10-08): the task Mikky looks at, wide tiles with words, the dots
  /// behind the apps, small controls. Else the home of 2026-10-02.
  final bool notch;

  /// The notch upright: the task over the apps, not beside them.
  final bool stacked;

  /// Tiles per row, rows per page; in the notch with nothing at work,
  /// the columns (the top: a third takes the task's place).
  final int columns, rows, idleColumns;

  /// A tile's height, its width (wide in the notch), the gaps.
  final double tile, tileWidth, gap, rowGap;

  /// Where the first row starts.
  final double gridTop;

  /// The bar (modes, tools): from the top, its height.
  final double barTop, bar;

  /// The foot (history, the pages' star, the environment): from the
  /// bottom, from the sides.
  final double foot, side;

  /// Mikky's size and his top left corner; on the notch with nothing at
  /// work, bigger (as `IslandMetrics.top.mikkyListIdle`).
  final double mikky, mikkyIdle;
  final Offset mikkyAt, mikkyIdleAt;

  bool get isTop => placement == HomePlacement.top;

  /// The corners away from the screen's edge.
  double get radius => 30;

  /// A page over the home (an agent's page): the island grows for the
  /// conversation — at the top as wide as the notch, 700 × 380 (user,
  /// 2026-10-05: « garder la largeur »); at the right to the
  /// phone-shaped 344 × 520 (2026-10-02). As `IslandMetrics.page`.
  Size get pageSize => isTop ? const Size(700, 380) : const Size(344, 520);
}
