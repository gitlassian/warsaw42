import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'app_text.dart';
import 'tokens.dart';

class DefiTextField extends StatefulWidget {
  const DefiTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.error,
    this.multiline = false,
    this.maxLength,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  /// Visible help text below the label; a placeholder never replaces it.
  final String? hint;

  /// What to correct; shown below the field.
  final String? error;
  final bool multiline;
  final int? maxLength;

  @override
  State<DefiTextField> createState() => _DefiTextFieldState();
}

class _DefiTextFieldState extends State<DefiTextField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(DefiTextField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
    borderRadius: AppRadius.control,
    borderSide: BorderSide(color: color, width: width),
  );

  @override
  Widget build(BuildContext context) {
    final invalid = widget.error != null;
    final idle = invalid ? _border(AppColors.danger, 2) : _border(AppColors.borderControl, 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s4,
      children: [
        Text(widget.label, style: AppTextStyles.label),
        if (widget.hint != null) DefiText(widget.hint!, tone: TextTone.secondary),
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          minLines: widget.multiline ? 4 : 1,
          maxLines: widget.multiline ? null : 1,
          maxLength: widget.maxLength,
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            counterText: '',
            contentPadding: const EdgeInsets.all(AppSpacing.s12),
            constraints: const BoxConstraints(minHeight: 48),
            enabledBorder: idle,
            border: idle,
            focusedBorder: _border(invalid ? AppColors.danger : AppColors.focus, 2),
          ),
        ),
        if (invalid) Text(widget.error!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
      ],
    );
  }
}

typedef ChoiceOption<T> = ({T value, String label});

/// Radio group styled as selectable rows.
class DefiChoiceGroup<T> extends StatelessWidget {
  const DefiChoiceGroup({
    super.key,
    required this.legend,
    required this.options,
    required this.value,
    required this.onChanged,
    this.error,
  });

  final String legend;
  final List<ChoiceOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s8,
      children: [
        Text(legend, style: AppTextStyles.label),
        for (final option in options) _option(option, option.value == value),
        if (error != null) Text(error!, style: AppTextStyles.body.copyWith(color: AppColors.danger)),
      ],
    );
  }

  Widget _option(ChoiceOption<T> option, bool checked) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: checked,
      label: option.label,
      excludeSemantics: true,
      onTap: () => onChanged(option.value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(option.value),
        child: AnimatedContainer(
          duration: AppDurations.feedback,
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.fromLTRB(checked ? 11 : 12, checked ? 7 : 8, checked ? 15 : 16, checked ? 7 : 8),
          decoration: BoxDecoration(
            color: checked ? AppColors.accentSoft : AppColors.surface,
            borderRadius: AppRadius.control,
            border: checked
                ? Border.all(color: AppColors.accent, width: 2)
                : Border.all(color: AppColors.borderControl),
          ),
          child: Row(
            spacing: AppSpacing.s12,
            children: [
              _Radio(checked: checked),
              Flexible(child: Text(option.label, style: AppTextStyles.body)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(color: checked ? AppColors.accent : AppColors.borderControl, width: 2),
      ),
      alignment: Alignment.center,
      child: checked
          ? const DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent),
              child: SizedBox.square(dimension: 10),
            )
          : null,
    );
  }
}

/// Expandable section for secondary details (hours, source text, device info).
class DefiDisclosure extends StatefulWidget {
  const DefiDisclosure({super.key, required this.title, required this.children, this.last = false});

  final String title;
  final List<Widget> children;

  /// The last section of a group also gets a bottom divider.
  final bool last;

  @override
  State<DefiDisclosure> createState() => _DefiDisclosureState();
}

class _DefiDisclosureState extends State<DefiDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    const divider = BorderSide(color: AppColors.border);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: divider, bottom: widget.last ? divider : BorderSide.none),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                  child: Row(
                    spacing: AppSpacing.s8,
                    children: [
                      Expanded(child: Text(widget.title, style: AppTextStyles.label)),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: AppDurations.feedback,
                        child: const AppIcon(AppIconName.expandMore, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.s8,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}

/// Range input with its first and last value labelled just below the track.
class DefiRangeSlider extends StatelessWidget {
  const DefiRangeSlider({
    super.key,
    required this.min,
    required this.max,
    required this.step,
    required this.value,
    required this.onChanged,
    required this.minLabel,
    required this.maxLabel,
    required this.label,
    this.valueText,
  });

  final double min;
  final double max;
  final double step;
  final double value;
  final ValueChanged<double> onChanged;

  /// Shown right under the two ends of the track.
  final String minLabel;
  final String maxLabel;

  /// Accessible name and spoken value.
  final String label;
  final String Function(double value)? valueText;

  @override
  Widget build(BuildContext context) {
    final scale = AppTextStyles.small(13).copyWith(color: AppColors.textSecondary, height: 1.2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 32,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.accent,
              overlayColor: const Color(0x00000000),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              trackShape: const RoundedRectSliderTrackShape(),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Semantics(
              label: label,
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: ((max - min) / step).round(),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                semanticFormatterCallback: valueText,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        // Pulled up into the hit area so the labels sit right under the track ends.
        Transform.translate(
          offset: const Offset(0, -AppSpacing.s4),
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(minLabel, style: scale),
                Text(maxLabel, style: scale),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
