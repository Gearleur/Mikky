import 'package:flutter/widgets.dart';

import 'motion.dart';
import 'surface.dart';
import 'tokens.dart';

/// Makes the text below selectable with the mouse, copied with Ctrl+C or
/// a right click (« Copier »): the agent's messages, commands, code.
class SelectableArea extends StatefulWidget {
  const SelectableArea({super.key, required this.child});

  final Widget child;

  @override
  State<SelectableArea> createState() => _SelectableAreaState();
}

class _SelectableAreaState extends State<SelectableArea> {
  final _focus = FocusNode(debugLabel: 'selection');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    // No Material here: the selection color has to be given.
    return DefaultSelectionStyle(
      selectionColor: ui.blue.withValues(alpha: .28),
      cursorColor: ui.text,
      child: SelectableRegion(
        focusNode: _focus,
        selectionControls: emptyTextSelectionControls,
        contextMenuBuilder: (context, state) => MikkyUiTheme(ui: ui, child: _CopyMenu(state: state)),
        child: widget.child,
      ),
    );
  }
}

const _labels = {ContextMenuButtonType.copy: 'Copier', ContextMenuButtonType.selectAll: 'Tout sélectionner'};

/// The right-click menu: a small capsule with « Copier » and « Tout
/// sélectionner », in the kit's style.
class _CopyMenu extends StatelessWidget {
  const _CopyMenu({required this.state});

  final SelectableRegionState state;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    final at = state.contextMenuAnchors.primaryAnchor;
    Widget item(String label, VoidCallback onTap) => Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: uiText(12.5, weight: FontWeight.w600, color: ui.text, height: 1.2),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned(
          left: at.dx,
          top: at.dy + 4,
          child: Surface(
            radius: 14,
            color: ui.thumb,
            shadows: [CssShadow(0, 0, 0, ui.line, spread: 1, inset: true), ...ui.shBar],
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final b in state.contextMenuButtonItems)
                  if (_labels[b.type] case final label?) item(label, () => b.onPressed?.call()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
