import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ui/controls/pixel_slider.dart';
import '../ui/controls/selectors.dart';
import '../ui/foundation/icons.dart';
import '../ui/foundation/motion.dart';
import '../ui/foundation/tokens.dart';

/// One focus stop and one accessible name for a setting or menu row.
class SettingActivator extends StatefulWidget {
  const SettingActivator({
    super.key,
    required this.label,
    required this.child,
    this.onPressed,
    this.value,
    this.increasedValue,
    this.decreasedValue,
    this.toggled,
    this.selected,
    this.slider = false,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
    this.onIncrease,
    this.onDecrease,
  });

  final String label;
  final Widget child;
  final VoidCallback? onPressed, onIncrease, onDecrease;
  final String? value, increasedValue, decreasedValue;
  final bool? toggled, selected;
  final bool slider;
  final FocusNode? focusNode;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<SettingActivator> createState() => _SettingActivatorState();
}

class _SettingActivatorState extends State<SettingActivator> {
  bool _focus = false;

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    value: widget.value,
    increasedValue: widget.increasedValue,
    decreasedValue: widget.decreasedValue,
    toggled: widget.toggled,
    selected: widget.selected,
    button: widget.toggled == null && !widget.slider,
    slider: widget.slider,
    enabled: widget.onPressed != null,
    excludeSemantics: true,
    onTap: widget.onPressed,
    onIncrease: widget.onIncrease,
    onDecrease: widget.onDecrease,
    child: Focus(
      canRequestFocus: false,
      onKeyEvent: widget.onKeyEvent,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) {
          if (focused) {
            Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
          }
        },
        onShowFocusHighlight: (value) => setState(() => _focus = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: _focus ? Border.all(color: MikkyUi.of(context).ink, width: 1.5) : null,
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

class SettingToggle extends StatelessWidget {
  const SettingToggle(this.label, {super.key, required this.value, this.detail, this.onChanged});

  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged == null ? null : () => onChanged!(!value);
    return SettingActivator(
      label: label,
      toggled: value,
      onPressed: change,
      child: Pressable(
        onTap: change,
        pressedScale: .99,
        child: Opacity(
          opacity: onChanged == null ? .45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Expanded(child: SettingLabel(label, detail: detail)),
                const SizedBox(width: 16),
                IgnorePointer(
                  child: MSwitch(value: value, onChanged: onChanged),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingLabel extends StatelessWidget {
  const SettingLabel(this.label, {super.key, this.detail});

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: uiText(TextSize.body, color: ui.text, weight: FontWeight.w500),
        ),
        if (detail != null) ...[
          const SizedBox(height: 3),
          Text(detail!, style: uiText(TextSize.caption, color: ui.text2, height: 1.4)),
        ],
      ],
    );
  }
}

class SettingChoice extends StatelessWidget {
  const SettingChoice(this.label, {super.key, required this.options, required this.selected, required this.onChanged});

  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  void _step(int delta) => onChanged((selected + delta) % options.length);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingLabel(label),
        const SizedBox(height: 8),
        SettingActivator(
          label: label,
          value: options[selected],
          increasedValue: options[(selected + 1) % options.length],
          decreasedValue: options[(selected - 1) % options.length],
          onPressed: () => _step(1),
          onIncrease: () => _step(1),
          onDecrease: () => _step(-1),
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
            final delta = switch (event.logicalKey) {
              LogicalKeyboardKey.arrowLeft => -1,
              LogicalKeyboardKey.arrowRight => 1,
              _ => 0,
            };
            if (delta == 0) return KeyEventResult.ignored;
            _step(delta);
            return KeyEventResult.handled;
          },
          child: Segmented(options: options, selected: selected, size: SegmentSize.xs, onChanged: onChanged),
        ),
      ],
    ),
  );
}

class SettingVolume extends StatelessWidget {
  const SettingVolume({super.key, required this.value, this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ui = MikkyUi.of(context);
    return Opacity(
      opacity: onChanged == null ? .45 : 1,
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: SettingLabel('Volume')),
              Text('${(value * 100).round()} %', style: uiText(TextSize.small, color: ui.text2, tabular: true)),
            ],
          ),
          PixelSlider(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class SettingAction extends StatelessWidget {
  const SettingAction(this.label, {super.key, this.detail, this.leading, required this.onPressed});

  final String label;
  final String? detail;
  final Widget? leading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SettingActivator(
    label: label,
    value: detail,
    onPressed: onPressed,
    child: HoverBuilder(
      builder: (context, hover) => Pressable(
        onTap: onPressed,
        pressedScale: .99,
        child: Container(
          decoration: BoxDecoration(
            color: hover ? MikkyUi.of(context).hover : null,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(child: SettingLabel(label, detail: detail)),
              const SizedBox(width: 12),
              MikkyIcon('right', size: 15, color: MikkyUi.of(context).text2),
            ],
          ),
        ),
      ),
    ),
  );
}
