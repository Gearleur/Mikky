import 'package:flutter/widgets.dart';

import '../ui/brand/app_glyph.dart';
import '../ui/brand/app_tile.dart';
import '../ui/brand/brand_logo.dart';
import '../ui/foundation/tokens.dart';
import 'home_app.dart';

/// The app's content on the shared tile, in the home and on the boards.
/// Square: its tool's logo. Wide: its software's sign, title and activity.
class HomeAppTile extends StatelessWidget {
  const HomeAppTile({super.key, required this.app, this.size = 64, this.width, this.onTap, this.onMenu});

  final HomeApp app;
  final double size;
  final double? width;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final wide = width != null;
    final brand = app.brand;
    final software = app.app;
    final sign = wide && software != null
        ? AppGlyph(software, size: 15)
        : (brand == null ? null : BrandLogo(brand, size: wide ? 15 : (size * .34).roundToDouble()));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: onMenu == null ? null : (_) => onMenu!(),
      child: AppTile(
        size: size,
        width: width,
        label: wide ? [app.name, ?software?.label].join(', ') : app.name,
        status: app.status,
        onTap: onTap,
        child: wide
            ? Padding(
                padding: const EdgeInsets.only(left: 11, right: 12),
                child: Row(
                  children: [
                    SizedBox(width: 16, child: Center(child: sign)),
                    const SizedBox(width: 9),
                    Expanded(child: HomeAppWords(app: app)),
                  ],
                ),
              )
            : (sign == null ? null : Center(child: sign)),
      ),
    );
  }
}

/// The same title and optional activity beside or inside a tile.
class HomeAppWords extends StatelessWidget {
  const HomeAppWords({super.key, required this.app});

  final HomeApp app;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final ink = AppTileInk.maybeOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          app.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: uiText(TextSize.small, weight: FontWeight.w600, color: ink?.text ?? ui.text, height: 1.25),
        ),
        if (app.line.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            app.line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: uiText(TextSize.caption, color: ink?.secondary ?? ui.text3, height: 1.25),
          ),
        ],
      ],
    );
  }
}
