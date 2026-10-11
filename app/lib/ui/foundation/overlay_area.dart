import 'package:flutter/widgets.dart';

/// Where [within] is in the Overlay above it: what floats in a window (a
/// menu, a sheet) is placed and kept in [OverlayArea.bounds]. Null while it
/// is not laid out yet, or has no Overlay.
OverlayArea? overlayArea(BuildContext within) {
  final overlay = Overlay.maybeOf(within);
  final area = within.findRenderObject() as RenderBox?;
  final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
  if (overlay == null || area == null || overlayBox == null || !area.hasSize) return null;
  return (
    overlay: overlay,
    overlayBox: overlayBox,
    area: area,
    bounds: MatrixUtils.transformRect(area.getTransformTo(overlayBox), Offset.zero & area.size),
  );
}

typedef OverlayArea = ({OverlayState overlay, RenderBox overlayBox, RenderBox area, Rect bounds});
