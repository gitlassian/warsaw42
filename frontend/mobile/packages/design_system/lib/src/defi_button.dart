import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'app_text.dart';
import 'defi_spinner.dart';
import 'tokens.dart';

enum ButtonVariant { primary, secondary, link }

class DefiButton extends StatelessWidget {
  const DefiButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.secondary,
    this.icon,
    this.loading = false,
    this.loadingLabel,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final AppIconName? icon;

  /// Keeps the button size, shows the status label and ignores repeated presses.
  final bool loading;
  final String? loadingLabel;

  /// Full width, like the web buttons; links and inline buttons size to their label.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final primary = variant == ButtonVariant.primary;
    final link = variant == ButtonVariant.link;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(expand && !link ? double.infinity : 0, primary ? 56 : 48)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: link ? 4 : 16, vertical: 12)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppRadius.control)),
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      textStyle: WidgetStatePropertyAll(
        link ? AppTextStyles.label.copyWith(decoration: TextDecoration.underline) : AppTextStyles.label,
      ),
      side: WidgetStateProperty.resolveWith((states) {
        if (variant != ButtonVariant.secondary || states.contains(WidgetState.disabled)) {
          return const BorderSide(color: Colors.transparent);
        }
        return BorderSide(
          color: states.contains(WidgetState.pressed) ? AppColors.accentPressed : AppColors.borderControl,
        );
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (link) return Colors.transparent;
        if (states.contains(WidgetState.disabled)) return AppColors.disabled;
        final pressed = states.contains(WidgetState.pressed);
        if (primary) return pressed ? AppColors.accentPressed : AppColors.accent;
        return pressed ? AppColors.accentSoft : AppColors.surface;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return AppColors.textMuted;
        if (primary) return AppColors.surface;
        return link && states.contains(WidgetState.pressed) ? AppColors.accentHover : AppColors.accent;
      }),
    );

    final text = loading && loadingLabel != null ? loadingLabel! : label;
    return TextButton(
      onPressed: onPressed == null ? null : (loading ? () {} : onPressed),
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.s8,
        children: [
          if (loading) const DefiSpinner() else if (icon != null) AppIcon(icon!),
          Flexible(child: Text(text, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}
