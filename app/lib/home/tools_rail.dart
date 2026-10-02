import 'package:flutter/widgets.dart';

import '../ui/brand_logo.dart';
import '../ui/edge_rail.dart';
import '../ui/motion.dart';

/// The tools Mikky can launch, on a rail attached to the window's edge
/// (the home's top right, 2026-10-02): their logos in overlapping white
/// discs. Under the mouse the discs move apart a little, on the
/// selectors' spring; pressed, they shrink like a button.
class ToolsRail extends StatefulWidget {
  const ToolsRail({super.key, this.tools = const [Brand.claude, Brand.codex], this.edge = RailEdge.right, this.height = 44, this.onPressed});

  final List<Brand> tools;
  final RailEdge edge;
  final double height;
  final VoidCallback? onPressed;

  @override
  State<ToolsRail> createState() => _ToolsRailState();
}

class _ToolsRailState extends State<ToolsRail> {
  bool _hover = false, _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disc = widget.height - 12;
    final on = widget.onPressed != null;
    return Semantics(
      button: on,
      label: 'Outils : ${widget.tools.map((t) => t.label).join(', ')}',
      child: MouseRegion(
        cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Listener(
          onPointerDown: on ? (_) => setState(() => _pressed = true) : null,
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: EdgeRail(
              edge: widget.edge,
              height: widget.height,
              child: AnimatedScale(
                scale: _pressed ? .94 : 1,
                duration: _pressed ? Motion.pressDown : Motion.pressUp,
                curve: _pressed ? Curves.easeOut : Motion.release,
                child: SpringValue(
                  target: _hover && on ? .4 : 0,
                  spring: Motion.thumb,
                  builder: (context, spread, _) => DiscStack(
                    size: disc,
                    spread: spread.clamp(0.0, 1.0),
                    children: [for (final t in widget.tools) BrandLogo(t, size: (disc * .56).roundToDouble())],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
