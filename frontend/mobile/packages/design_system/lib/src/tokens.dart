import 'package:flutter/painting.dart';

// Source of truth: /DESIGN.md. Keep in sync with web src/design-system/tokens.css.
abstract final class AppColors {
  static const accent = Color(0xFF237A57);
  static const accentHover = Color(0xFF1D6B4B);
  static const accentPressed = Color(0xFF185A40);
  static const accentSoft = Color(0xFFEAF5EE);
  static const background = Color(0xFFF5F8F6);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF17231D);
  static const textSecondary = Color(0xFF506158);
  static const textMuted = Color(0xFF5D6E63);
  static const border = Color(0xFFD8E2DC);
  static const borderControl = Color(0xFF75857B);
  static const focus = Color(0xFF125A3C);
  static const warning = Color(0xFF8A570A);
  static const warningSoft = Color(0xFFFFF5DF);
  static const danger = Color(0xFFB23B36);
  static const dangerSoft = Color(0xFFFCEDEC);
  static const unknown = Color(0xFF56645B);
  static const unknownSoft = Color(0xFFEEF2EF);
  static const location = Color(0xFF2869B1);
  static const disabled = Color(0xFFEDF1EE);
}

abstract final class AppSpacing {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s48 = 48.0;
}

abstract final class AppRadius {
  static const control = BorderRadius.all(Radius.circular(12));
  static const sheet = BorderRadius.vertical(top: Radius.circular(24));
  static const pill = BorderRadius.all(Radius.circular(999));
}
