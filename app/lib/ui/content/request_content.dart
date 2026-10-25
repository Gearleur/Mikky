import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../foundation/tokens.dart';
import '../pixels/pixel_fx.dart';

/// Keep wheel steps readable without changing touch or scrollbar dragging.
class RequestScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _RequestPosition(physics: physics, context: context, oldPosition: oldPosition);
}

class _RequestPosition extends ScrollPositionWithSingleContext {
  _RequestPosition({required super.physics, required super.context, super.oldPosition});

  @override
  void pointerScroll(double delta) => super.pointerScroll((delta * .5).clamp(-48.0, 48.0));
}

/// Align the start, including when the form is taller than its viewport.
void revealRequest(GlobalKey anchor, ScrollController scroll, {bool animate = false}) {
  final target = anchor.currentContext?.findRenderObject();
  if (target == null || !scroll.hasClients) return;
  final offset = RenderAbstractViewport.of(target)
      .getOffsetToReveal(target, 0)
      .offset
      .clamp(scroll.position.minScrollExtent, scroll.position.maxScrollExtent);
  if (animate) {
    scroll.animateTo(offset, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  } else {
    scroll.jumpTo(offset);
  }
}

/// A request's pixel edge and content, with its actions kept in sight.
class RequestContent extends StatelessWidget {
  const RequestContent({
    super.key,
    required this.child,
    required this.actions,
    this.heading,
    this.fill = false,
    this.compact = false,
    this.before = const [],
    this.scroll,
    this.contentAnchor,
  });

  final Widget child, actions;
  final Widget? heading;
  final bool fill, compact;
  final List<Widget> before;
  final ScrollController? scroll;
  final GlobalKey? contentAnchor;

  @override
  Widget build(BuildContext context) {
    final indent = compact ? 18.0 : 24.0;
    final heading = this.heading == null
        ? null
        : Padding(
            padding: EdgeInsets.only(left: indent, bottom: 3),
            child: this.heading,
          );
    // With conversation context, the steps belong to the form below it.
    // Standalone forms can keep their heading pinned above the choices.
    final pinnedHeading = fill && before.isEmpty;
    final content = Column(
      key: contentAnchor,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!pinnedHeading && heading != null) heading,
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
        if (pinnedHeading && heading != null) heading,
        if (fill)
          Expanded(
            child: _RequestScroll(
              before: before,
              scroll: scroll,
              anchor: contentAnchor,
              showScrollbar: !compact,
              child: content,
            ),
          )
        else ...[
          ...before,
          content,
        ],
        SizedBox(height: compact ? 4 : 8),
        actions,
      ],
    );
  }
}

/// Gives long forms an observable, draggable scroll affordance.
class _RequestScroll extends StatefulWidget {
  const _RequestScroll({
    required this.child,
    required this.before,
    required this.showScrollbar,
    this.scroll,
    this.anchor,
  });
  final Widget child;
  final List<Widget> before;
  final ScrollController? scroll;
  final GlobalKey? anchor;
  final bool showScrollbar;

  @override
  State<_RequestScroll> createState() => _RequestScrollState();
}

class _RequestScrollState extends State<_RequestScroll> {
  late final _owned = RequestScrollController();
  ScrollController get _scroll => widget.scroll ?? _owned;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.before.isEmpty || !_scroll.hasClients || _scroll.position.maxScrollExtent <= 24) return;
      if (widget.anchor case final anchor?) revealRequest(anchor, _scroll);
    });
  }

  @override
  void dispose() {
    _owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = CustomScrollView(
      controller: _scroll,
      physics: const ClampingScrollPhysics(),
      slivers: [
        if (widget.before.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(right: 8, bottom: 20),
            sliver: SliverList.list(children: widget.before),
          ),
        SliverPadding(
          padding: const EdgeInsets.only(right: 8),
          sliver: SliverToBoxAdapter(child: widget.child),
        ),
      ],
    );
    if (!widget.showScrollbar) return content;
    return RawScrollbar(
      controller: _scroll,
      thumbVisibility: true,
      interactive: true,
      thickness: 3,
      radius: const Radius.circular(3),
      thumbColor: MikkyUi.of(context).text3.withValues(alpha: .5),
      child: content,
    );
  }
}
