import 'package:flutter/widgets.dart';

import 'app_icon.dart';
import 'app_text.dart';
import 'tokens.dart';

enum IconButtonVariant {
  /// Round map control.
  floating,

  /// Inside a panel.
  plain,
}

class DefiIconButton extends StatelessWidget {
  const DefiIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.variant = IconButtonVariant.plain,
    this.pressed,
    this.text,
  });

  final AppIconName icon;

  /// Accessible name.
  final String label;
  final VoidCallback? onPressed;
  final IconButtonVariant variant;

  /// Toggle state; null for plain buttons.
  final bool? pressed;

  /// Short visible caption under the icon (floating map controls), e.g. "Filtry".
  final String? text;

  @override
  Widget build(BuildContext context) {
    final on = pressed ?? false;
    final tile = text != null;
    final floating = tile || variant == IconButtonVariant.floating;

    final (Color bg, Color fg, Color border, double borderWidth) = switch ((floating, on)) {
      // On the map a switched-on control is solid green, not a faint tint.
      (true, true) => (AppColors.accent, AppColors.surface, AppColors.accent, 2.0),
      (true, false) => (AppColors.surface, AppColors.accent, AppColors.accent, 2.0),
      (false, true) => (AppColors.accentSoft, AppColors.accent, AppColors.accent, 1.0),
      (false, false) => (const Color(0x00FFFFFF), AppColors.textPrimary, const Color(0x00FFFFFF), 1.0),
    };

    final glyph = AppIcon(icon, color: fg, filled: on);
    return Semantics(
      button: true,
      label: label,
      toggled: pressed,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: tile ? 56 : 48,
          height: tile ? 56 : 48,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: borderWidth),
            borderRadius: tile ? AppRadius.control : AppRadius.pill,
            boxShadow: floating ? AppShadows.control : null,
          ),
          alignment: Alignment.center,
          child: tile
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    glyph,
                    Text(
                      text!,
                      style: AppTextStyles.small(11, weight: FontWeight.w600).copyWith(color: fg, height: 14 / 11),
                    ),
                  ],
                )
              : glyph,
        ),
      ),
    );
  }
}
