import 'package:flutter/widgets.dart';

import 'app_icon.dart';
import 'app_text.dart';
import 'tokens.dart';
import 'tone.dart';

/// In-panel message that stays until the situation is resolved (DESIGN.md §8).
class DefiNotice extends StatelessWidget {
  const DefiNotice({
    super.key,
    required this.title,
    this.tone = Tone.neutral,
    this.icon,
    this.child,
    this.actions = const [],
  });

  final String title;
  final Tone tone;
  final AppIconName? icon;

  /// Body text or content under the title.
  final Widget? child;

  /// The next steps the user can take, e.g. a retry button.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(color: tone.bg, borderRadius: AppRadius.control),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.s12,
          children: [
            AppIcon(icon ?? tone.icon, color: tone.fg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.s8,
                children: [
                  Text(title, style: AppTextStyles.label.copyWith(color: tone.fg)),
                  if (child != null)
                    DefaultTextStyle(
                      style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
                      child: child!,
                    ),
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSpacing.s8,
                        children: actions,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status as colored text without a chip: the words carry the meaning, the tone color reinforces it.
class DefiStatusText extends StatelessWidget {
  const DefiStatusText(this.text, {super.key, required this.tone, this.icon});

  final String text;
  final Tone tone;
  final AppIconName? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.s8,
      children: [
        if (icon != null) AppIcon(icon!, size: 20, color: tone.fg),
        Flexible(
          child: Text(text, style: AppTextStyles.label.copyWith(color: tone.fg)),
        ),
      ],
    );
  }
}
