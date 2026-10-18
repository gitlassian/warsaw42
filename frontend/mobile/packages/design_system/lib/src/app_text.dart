import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Type roles from DESIGN.md §3.
enum TextVariant {
  time(AppTextStyles.time),
  title(AppTextStyles.title),
  name(AppTextStyles.name),
  heading(AppTextStyles.heading),
  body(AppTextStyles.body),
  label(AppTextStyles.label),
  meta(AppTextStyles.meta);

  const TextVariant(this.style);
  final TextStyle style;
}

enum TextTone {
  primary(AppColors.textPrimary),
  secondary(AppColors.textSecondary),
  muted(AppColors.textMuted),
  accent(AppColors.accent);

  const TextTone(this.color);
  final Color color;
}

abstract final class AppTextStyles {
  static const _family = 'NotoSans';
  static const _package = 'design_system';
  static const _even = TextLeadingDistribution.even;
  static const _tabular = [FontFeature.tabularFigures()];

  static const time = TextStyle(
    fontFamily: _family,
    package: _package,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
    leadingDistribution: _even,
  );
  static const title = TextStyle(
    fontFamily: _family,
    package: _package,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );
  static const name = TextStyle(
    fontFamily: _family,
    package: _package,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );
  static const heading = TextStyle(
    fontFamily: _family,
    package: _package,
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );
  static const body = TextStyle(
    fontFamily: _family,
    package: _package,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    leadingDistribution: _even,
  );
  static const label = TextStyle(
    fontFamily: _family,
    package: _package,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    leadingDistribution: _even,
  );
  static const meta = TextStyle(
    fontFamily: _family,
    package: _package,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    fontFeatures: _tabular,
    leadingDistribution: _even,
  );

  /// Small captions: map control labels, slider scales, hints (11–13 px on web).
  static TextStyle small(double size, {FontWeight weight = FontWeight.w400}) => TextStyle(
    fontFamily: _family,
    package: _package,
    fontSize: size,
    height: 1.25,
    fontWeight: weight,
    fontFeatures: _tabular,
    leadingDistribution: _even,
  );
}

class DefiText extends StatelessWidget {
  const DefiText(this.text, {super.key, this.variant = TextVariant.body, this.tone = TextTone.primary, this.maxLines});

  final String text;
  final TextVariant variant;
  final TextTone tone;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: variant.style.copyWith(color: tone.color),
    );
  }
}
