import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/lib/aed_status.dart';
import 'package:defiwawa/features/aeds/lib/availability.dart';

/// Compact name in a white pill over the map (DESIGN.md §6). The mobile header has no info button.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: 'DefiWawa',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onHome,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(AppSpacing.s12, AppSpacing.s8, AppSpacing.s16, AppSpacing.s8),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.pill,
            boxShadow: AppShadows.floating,
          ),
          alignment: Alignment.center,
          // [D]efiWawa lockup: the symbol is the D. Smaller than on wide web screens (24).
          child: SvgPicture.asset('assets/brand/defiwawa-horizontal.svg', height: 18),
        ),
      ),
    );
  }
}

/// One tap group for the filter button and its menu, so a tap anywhere else closes the menu.
const filtersTapGroup = #mapFilters;

/// Floating map controls; positioned around the sheet by the page.
/// Layers, time and filters fold behind a small "more" button, with [locate] right above it while folded.
class MapControls extends StatelessWidget {
  const MapControls({
    super.key,
    required this.moreOpen,
    required this.coverageShown,
    required this.placementShown,
    required this.timeOpen,
    required this.filtersOpen,
    required this.onToggleMore,
    required this.onToggleCoverage,
    required this.onTogglePlacement,
    required this.onToggleTime,
    required this.onToggleFilters,
    required this.locate,
  });

  final bool moreOpen;
  final bool coverageShown;
  final bool placementShown;
  final bool timeOpen;
  final bool filtersOpen;
  final VoidCallback onToggleMore;
  final VoidCallback onToggleCoverage;
  final VoidCallback onTogglePlacement;
  final VoidCallback onToggleTime;
  final VoidCallback onToggleFilters;
  final Widget locate;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      DefiIconButton(
        icon: AppIconName.layers,
        label: 'Warstwa: Odległość do najbliższego AED',
        text: 'Zasięg',
        pressed: coverageShown,
        onPressed: onToggleCoverage,
      ),
      DefiIconButton(
        icon: AppIconName.addLocation,
        label: 'Gdzie dodać AED: miejsca, które poprawią zasięg o wybranej porze',
        text: 'Nowe',
        pressed: placementShown,
        onPressed: onTogglePlacement,
      ),
      DefiIconButton(
        icon: AppIconName.schedule,
        label: timeOpen ? 'Ukryj wybór godziny' : 'Sprawdź dostępność o innej porze',
        text: 'Pora',
        pressed: timeOpen,
        onPressed: onToggleTime,
      ),
      TapRegion(
        groupId: filtersTapGroup,
        child: DefiIconButton(
          icon: AppIconName.filterList,
          label: 'Filtry AED',
          text: 'Filtry',
          pressed: filtersOpen,
          onPressed: onToggleFilters,
        ),
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      // Folded: the locate square's 48 px hit area adds 4 px under its 40 px face, keeping the 8 px gap.
      spacing: moreOpen ? AppSpacing.s8 : AppSpacing.s4,
      children: [
        if (moreOpen)
          // Unfolded tiles rise out of the button, nearest first.
          for (final (i, tile) in tiles.indexed)
            _RiseIn(
              delay: Duration(milliseconds: 40 * (tiles.length - 1 - i)),
              child: tile,
            )
        else
          locate,
        _MoreButton(open: moreOpen, onPressed: onToggleMore),
      ],
    );
  }
}

/// Small white square with the location glyph: right above the "more" button, or alone while navigating.
class LocateButton extends StatelessWidget {
  const LocateButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Pokaż moją lokalizację',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.control,
              boxShadow: AppShadows.floating,
            ),
            child: AppIcon(
              AppIconName.myLocation,
              size: 20,
              color: onPressed == null ? AppColors.textMuted : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Smaller uncaptioned version of the tiles it unfolds; solid green while they are shown.
class _MoreButton extends HookWidget {
  const _MoreButton({required this.open, required this.onPressed});

  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final down = useState(false);
    final fg = open ? AppColors.surface : AppColors.accent;
    return Semantics(
      button: true,
      expanded: open,
      label: open ? 'Ukryj opcje mapy' : 'Więcej opcji mapy',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        onTapDown: (_) => down.value = true,
        onTapUp: (_) => down.value = false,
        onTapCancel: () => down.value = false,
        child: AnimatedScale(
          scale: down.value ? 0.94 : 1,
          duration: AppDurations.feedback,
          child: AnimatedContainer(
            duration: AppDurations.feedback,
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: open ? AppColors.accent : AppColors.surface,
              border: Border.all(color: AppColors.accent, width: 2),
              borderRadius: AppRadius.control,
              boxShadow: AppShadows.control,
            ),
            // Keyed so the glyph remounts and replays its turn-in on every toggle.
            child: TweenAnimationBuilder<double>(
              key: ValueKey(open),
              tween: Tween(begin: 0, end: 1),
              duration: AppDurations.feedback,
              curve: Curves.easeOut,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.rotate(
                  angle: -pi / 2 * (1 - t),
                  child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
                ),
              ),
              child: open ? AppIcon(AppIconName.close, color: fg) : AppIcon(AppIconName.more, size: 32, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and rises into place after [delay] (CSS `animation-delay` with `backwards` fill).
class _RiseIn extends StatelessWidget {
  const _RiseIn({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final total = AppDurations.panel + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: Curves.easeOut),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
        ),
      ),
      child: child,
    );
  }
}

const _filterOptions = [
  (AedAvailability.available, AppIconName.checkCircle, 'Otwarte'),
  (AedAvailability.unavailable, AppIconName.lock, 'Zamknięte i niedostępne'),
];

/// AED groups: green = shown, white = off; with every group off the map shows all AEDs.
/// Opens to the left of the control column and grows up from the filter button.
class FilterMenu extends StatelessWidget {
  const FilterMenu({super.key, required this.filters, required this.onToggle, required this.onClose});

  final AedFilters filters;
  final ValueChanged<AedAvailability> onToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final anyOn = filters.available || filters.unavailable;
    return TapRegion(
      groupId: filtersTapGroup,
      onTapOutside: (_) => onClose(),
      child: Semantics(
        label: 'Filtry AED',
        container: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 240, maxWidth: MediaQuery.sizeOf(context).width - 96),
          child: IntrinsicWidth(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s8),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.control,
                boxShadow: AppShadows.panel,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.s8,
                children: [
                  for (final (group, icon, label) in _filterOptions)
                    _Toggle(
                      on: group == AedAvailability.available ? filters.available : filters.unavailable,
                      icon: icon,
                      label: label,
                      onTap: () => onToggle(group),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                    child: Text(
                      anyOn ? 'Pokazujemy tylko zaznaczone grupy.' : 'Brak filtrów: pokazujemy wszystkie AED.',
                      style: AppTextStyles.small(13).copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.on, required this.icon, required this.label, required this.onTap});

  final bool on;
  final AppIconName icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? AppColors.surface : AppColors.textPrimary;
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.feedback,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
          decoration: BoxDecoration(
            color: on ? AppColors.accent : AppColors.surface,
            border: Border.all(color: on ? AppColors.accent : AppColors.borderControl),
            borderRadius: AppRadius.control,
          ),
          child: Row(
            spacing: AppSpacing.s12,
            children: [
              AppIcon(icon, color: fg),
              Flexible(
                child: Text(label, style: AppTextStyles.label.copyWith(color: fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _dayShort = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];
const _stepMin = 15;
const _lastStep = 24 * 60 - _stepMin;

/// Weekday chips and a time slider: shows which AEDs are available at any hour of the week.
class TimeBar extends StatelessWidget {
  const TimeBar({super.key, required this.at, required this.live, required this.onChange, required this.onNow});

  final DateTime at;
  final bool live;
  final void Function(int day, int minutes) onChange;
  final VoidCallback onNow;

  @override
  Widget build(BuildContext context) {
    final (:day, :minutes) = warsawClock(at);
    final sliderValue = minutes ~/ _stepMin * _stepMin;
    final small = AppTextStyles.small(14, weight: FontWeight.w600).copyWith(height: 20 / 14);

    Widget chip(String text, {required bool on, required String label, required VoidCallback onTap}) => Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.accent : AppColors.surface,
            border: Border.all(color: on ? AppColors.accent : AppColors.borderControl),
            borderRadius: AppRadius.pill,
          ),
          child: Text(text, style: small.copyWith(color: on ? AppColors.surface : AppColors.textPrimary)),
        ),
      ),
    );

    return Semantics(
      label: 'Podgląd dostępności o wybranej porze',
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.s12, AppSpacing.s8, AppSpacing.s12, AppSpacing.s12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.control,
          boxShadow: AppShadows.panel,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s8,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Row(
                spacing: AppSpacing.s8,
                children: [
                  Expanded(
                    child: DefiText(
                      '${live ? 'Teraz' : weekdayNames[day]}, ${clockText(minutes)}',
                      variant: TextVariant.label,
                    ),
                  ),
                  if (!live)
                    Semantics(
                      button: true,
                      child: GestureDetector(
                        onTap: onNow,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s4),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.accent),
                            borderRadius: AppRadius.pill,
                          ),
                          child: Text('Teraz', style: small.copyWith(color: AppColors.accent)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              spacing: AppSpacing.s4,
              children: [
                for (final (i, name) in _dayShort.indexed)
                  Expanded(
                    child: chip(name, on: i == day, label: weekdayNames[i], onTap: () => onChange(i, sliderValue)),
                  ),
              ],
            ),
            DefiRangeSlider(
              label: 'Godzina',
              min: 0,
              max: _lastStep.toDouble(),
              step: _stepMin.toDouble(),
              value: sliderValue.toDouble(),
              valueText: (v) => clockText(v.round()),
              onChanged: (v) => onChange(day, v.round()),
              minLabel: clockText(0),
              maxLabel: clockText(_lastStep),
            ),
            if (!live)
              Text(
                'Podgląd godzin dostępu. Trasy liczymy dla chwili obecnej.',
                style: AppTextStyles.small(13).copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
