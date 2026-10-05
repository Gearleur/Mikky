import 'package:flutter/widgets.dart';
import 'package:mikky_engine/mikky_engine.dart';

import 'buttons.dart';
import 'selection.dart';
import 'side.dart';

/// Where Mikky stands beside a thread (2026-10-05, chosen among three
/// trials: « au milieu »).
enum MikkyBeside {
  /// At the top, under the back button.
  top,

  /// In the middle of the page's height.
  middle,

  /// At the bottom, beside the field.
  bottom,
}

/// A page with a thread — an agent's page, a new chat — laid out the same
/// everywhere (2026-10-05: « tout pareil »): no title, the thread up to the
/// top under floating buttons, blurred; the field at the bottom, off the
/// window's foot; in the notch, Mikky on the left ([mikky]), the thread
/// and the field on his right; elsewhere a centered reading column.
class ThreadPage extends StatelessWidget {
  const ThreadPage({
    super.key,
    required this.back,
    this.children = const [],
    this.empty,
    this.composer,
    this.note,
    this.menu,
    this.overlay,
    this.mikky,
    this.drawMikky = true,
    this.mikkyState = MikkyState.idle,
    this.scroll,
  });

  final VoidCallback back;

  /// The thread.
  final List<Widget> children;

  /// In the middle of the thread's room when it is empty.
  final Widget? empty;

  /// The field; null: [note] instead (a read-only session).
  final Widget? composer;
  final Widget? note;

  /// The ··· menu; null: no button.
  final VoidCallback? menu;

  /// At the top, in the middle (the spell's star).
  final Widget? overlay;

  /// Mikky's place beside the thread; null: the centered reading column.
  final MikkyBeside? mikky;

  /// False: the island draws its own Mikky there (the app).
  final bool drawMikky;
  final MikkyState mikkyState;
  final ScrollController? scroll;

  /// Mikky's column, and the thread's margin on the right, beside him.
  static const gutter = 128.0, rightMargin = 28.0;

  @override
  Widget build(BuildContext context) {
    final beside = mikky;
    Widget column(Widget child) => beside == null
        ? ReadingColumn(child: child)
        : Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: readingWidth), child: child));
    final left = beside == null ? 16.0 : gutter, right = beside == null ? 16.0 : rightMargin;
    final bottom = composer == null ? 62.0 : 88.0;
    return Stack(
      children: [
        // The thread fills the page and passes under the buttons and the
        // field, blurred (user request, 2026-09-30).
        Positioned.fill(
          child: SingleChildScrollView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(left, 62, right, bottom),
            child: SelectableArea(
              child: column(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
            ),
          ),
        ),
        if (children.isEmpty && empty != null) Positioned.fill(left: left, right: right, top: 62, bottom: bottom, child: Center(child: empty)),
        // Softer on top (user request, 2026-09-30: « trop puissant »).
        const Positioned(top: 0, left: 0, right: 0, child: TopBlur()),
        // Only behind the field, not above it (user request, 2026-09-30).
        Positioned(left: 0, right: 0, bottom: 0, child: EdgeBlur(top: false, height: composer == null ? 50 : 64)),
        if (overlay != null) Positioned(top: 20, left: 0, right: 0, child: Center(child: overlay)),
        SideHead(
          leading: RoundButton('left', size: 34, onPressed: back, tooltip: 'Retour'),
          actions: [if (menu != null) RoundButton.menu(size: 34, tooltip: 'Menu', onPressed: menu)],
        ),
        // Off the window's foot (2026-10-05: « trop petit » at 12).
        if (composer != null) Positioned(left: beside == null ? 20 : gutter, right: beside == null ? 20 : rightMargin, bottom: 20, child: column(composer!)),
        if (composer == null && note != null) Positioned(left: left, right: right, bottom: 20, child: column(note!)),
        if (beside != null && drawMikky)
          Positioned(
            left: 22,
            top: beside == MikkyBeside.top ? 58 : 0,
            bottom: beside == MikkyBeside.bottom ? 12 : 0,
            child: Align(
              alignment: switch (beside) {
                MikkyBeside.top => Alignment.topCenter,
                MikkyBeside.middle => Alignment.center,
                MikkyBeside.bottom => Alignment.bottomCenter,
              },
              // 84 px, in his agent's state, looking at the thread.
              child: MiniMikky(size: 84, badge: false, state: mikkyState, look: const Offset(1, .2)),
            ),
          ),
      ],
    );
  }
}
