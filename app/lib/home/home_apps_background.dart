import 'package:flutter/widgets.dart';

import '../ui/foundation/tokens.dart';

/// The notch's faint grey wash, fading out towards Mikky and his task.
/// The same background runs horizontally at the top, vertically at the right.
class HomeAppsBackground extends StatelessWidget {
  const HomeAppsBackground({super.key, required this.axis, required this.goneAt, required this.solidFrom});

  final Axis axis;
  final double goneAt, solidFrom;

  @override
  Widget build(BuildContext context) {
    final tint = MikkyUi.of(context).appsBackground;
    final horizontal = axis == Axis.horizontal;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final extent = horizontal ? box.maxWidth : box.maxHeight;
          if (extent <= 0) return const SizedBox.shrink();
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
                end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
                colors: [tint.withValues(alpha: 0), tint.withValues(alpha: 0), tint],
                stops: [0, (goneAt / extent).clamp(0, 1), (solidFrom / extent).clamp(0, 1)],
              ),
            ),
          );
        },
      ),
    );
  }
}
