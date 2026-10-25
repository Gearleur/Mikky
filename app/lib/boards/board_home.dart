import 'package:flutter/widgets.dart';

import '../home/home_app.dart';
import '../ui/brand/brand_logo.dart';
import '../ui/controls/buttons.dart';
import '../ui/controls/environment_selector.dart';
import '../ui/controls/page_dots.dart';
import '../ui/foundation/status.dart';
import '../ui/foundation/tokens.dart';

// The home at the right (2026-10-02); the one at the top is the notch
// (`board_notch.dart`). Its components are on the Composants board. The
// HTML mockups of `docs/notch_haut/` are only a picture of the goal.

/// Components on the island's color, for the boards. [edge]: flat on the
/// right, as against the screen's edge, and the content right up to it.
class BoardPane extends StatelessWidget {
  const BoardPane({super.key, required this.child, this.width = 300, this.height, this.edge = false});

  final Widget child;
  final double width;
  final double? height;
  final bool edge;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    const r = Radius.circular(Radii.xl);
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.fromLTRB(18, 18, edge ? 0 : 18, 18),
      decoration: BoxDecoration(
        color: ui.island,
        borderRadius: edge ? const BorderRadius.horizontal(left: r) : const BorderRadius.all(r),
        border: edge
            ? Border(
                left: BorderSide(color: ui.line),
                top: BorderSide(color: ui.line),
                bottom: BorderSide(color: ui.line),
              )
            : Border.all(color: ui.line),
      ),
      child: child,
    );
  }
}

/// The arrows and the dots of the home's pages, to try.
class PagerTry extends StatelessWidget {
  const PagerTry({super.key, required this.page, required this.set, this.count = 4});

  final int page, count;
  final ValueChanged<int> set;

  @override
  Widget build(BuildContext context) {
    Widget arrow(bool next) {
      final shown = next ? page < count - 1 : page > 0;
      return Opacity(
        opacity: shown ? 1 : 0,
        child: RoundButton(
          next ? 'right' : 'left',
          size: 28,
          onPressed: shown ? () => set(page + (next ? 1 : -1)) : null,
        ),
      );
    }

    return Row(
      children: [
        arrow(false),
        Expanded(
          child: Center(
            child: PageDots(count: count, page: page, onSelect: set),
          ),
        ),
        arrow(true),
      ],
    );
  }
}

/// « Choisir l'environnement » in a little window of its own (with an
/// Overlay, as the app's): the real menu opens in it.
class SelectorTry extends StatefulWidget {
  const SelectorTry({super.key, this.small = false});

  final bool small;

  @override
  State<SelectorTry> createState() => _SelectorTryState();
}

class _SelectorTryState extends State<SelectorTry> {
  MikkyEnvironment _environment = MikkyEnvironment.local;
  late final OverlayEntry _layer = OverlayEntry(
    builder: (inner) => Stack(
      children: [
        Positioned(
          top: widget.small ? null : 18,
          bottom: widget.small ? 18 : null,
          right: 18,
          child: EnvironmentSelector(
            selected: _environment,
            small: widget.small,
            menuWithin: inner,
            onChanged: (e) {
              _environment = e;
              _layer.markNeedsBuild();
            },
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _layer.remove();
    _layer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Container(
      width: 300,
      height: 250,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ui.island,
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: ui.line),
      ),
      child: Overlay(initialEntries: [_layer]),
    );
  }
}

// ------------------------------------------------------------------ boards

/// Apps as the app shows them today: the tool's logo and the agent's state
/// (until the apps get their drawing).
const sampleApps = [
  HomeApp(id: 'a1', name: 'Met à jour le site', brand: Brand.codex, status: UiStatus.approval),
  HomeApp(id: 'a2', name: 'Corrige les tests du moteur', brand: Brand.claude, status: UiStatus.working),
  HomeApp(id: 'a3', name: 'Prépare le plan de l’API', brand: Brand.codex, status: UiStatus.working),
  HomeApp(id: 'a4', name: 'Traduis la documentation', brand: Brand.claude, status: UiStatus.limited),
  HomeApp(id: 'a5', name: 'Résume la spec', brand: Brand.claude, status: UiStatus.finished),
  HomeApp(id: 'a6', name: 'Ajoute les tests du lecteur', brand: Brand.codex, status: UiStatus.finished),
  HomeApp(id: 'a7', name: 'Nettoie les imports', brand: Brand.codex, status: UiStatus.working),
  HomeApp(id: 'a8', name: 'Corrige le clic en dehors', brand: Brand.claude, status: UiStatus.finished),
];
