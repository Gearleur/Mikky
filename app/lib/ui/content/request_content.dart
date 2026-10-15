import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';
import '../pixels/pixel_fx.dart';

/// A request's pixel edge and content, with its actions kept in sight.
class RequestContent extends StatelessWidget {
  const RequestContent({
    super.key,
    required this.child,
    required this.actions,
    this.heading,
    this.fill = false,
    this.compact = false,
  });

  final Widget child, actions;
  final Widget? heading;
  final bool fill, compact;

  @override
  Widget build(BuildContext context) {
    final indent = compact ? 18.0 : 24.0;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading != null)
          Padding(
            padding: EdgeInsets.only(left: indent, bottom: 3),
            child: heading,
          ),
        Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(left: indent),
              child: child,
            ),
            Positioned(left: 0, top: 4, bottom: 4, child: PixelEdge.waiting(MikkyUi.of(context))),
          ],
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (fill) Expanded(child: SingleChildScrollView(child: content)) else content,
        SizedBox(height: compact ? 4 : 8),
        actions,
      ],
    );
  }
}
