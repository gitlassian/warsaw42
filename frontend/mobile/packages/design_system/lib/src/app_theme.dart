import 'package:flutter/material.dart';

import 'app_text.dart';
import 'tokens.dart';

abstract final class AppTheme {
  // Explicit scheme so platform/seed defaults never override the app palette.
  static final light = ThemeData(
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: AppColors.surface,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.borderControl,
      outlineVariant: AppColors.border,
      error: AppColors.danger,
      onError: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'NotoSans',
    package: 'design_system',
    textTheme: TextTheme(
      bodyLarge: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
      bodyMedium: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionHandleColor: AppColors.accent,
      selectionColor: AppColors.accentSoft,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}
