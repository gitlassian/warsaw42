import 'package:flutter/painting.dart';

import 'app_icon.dart';
import 'tokens.dart';

/// Semantic color pairs (DESIGN.md §2) with the default icon of each.
enum Tone {
  accent(AppColors.accent, AppColors.accentSoft, AppIconName.checkCircle),
  neutral(AppColors.unknown, AppColors.unknownSoft, AppIconName.info),
  warning(AppColors.warning, AppColors.warningSoft, AppIconName.warning),
  danger(AppColors.danger, AppColors.dangerSoft, AppIconName.error);

  const Tone(this.fg, this.bg, this.icon);

  final Color fg;
  final Color bg;
  final AppIconName icon;
}
