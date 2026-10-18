import 'dart:async';
import 'dart:math';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/app/router/route_paths.dart';
import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/lib/availability.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/coverage/models/coverage.dart';
import 'package:defiwawa/features/coverage/providers/coverage_provider.dart';

/// "Odległość do najbliższego AED" coverage layer mode (DESIGN.md §11).
class CoveragePanel extends HookConsumerWidget {
  const CoveragePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CoverageState(:scenario, :thresholdM, :status, :layer, :selected) = ref.watch(coverageProvider);
    final coverage = ref.read(coverageProvider.notifier);
    final now = ref.watch(aedsProvider.select((s) => s.now));
    final live = ref.watch(aedsProvider.select((s) => s.live));
    final nearestId = selected?.nearestAedId;
    final nearestAed = ref.watch(aedsProvider.select((s) => nearestId == null ? null : s.byId[nearestId]));

    // The slider moves freely; the layer is recalculated once it rests.
    final radius = useState(thresholdM);
    useEffect(() {
      if (radius.value == thresholdM) return null;
      final timer = Timer(const Duration(milliseconds: 250), () => coverage.setQuery(thresholdM: radius.value));
      return timer.cancel;
    }, [radius.value, thresholdM]);

    // The time-based scenario follows the one map time (live: the clock); scenario changes reload on their own.
    useEffect(() {
      Future.microtask(() {
        final current = ref.read(coverageProvider);
        if (current.scenario == CoverageScenario.availableAt || current.status == CoverageStatus.idle) coverage.load();
      });
      return null;
    }, [now]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s24,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s12,
          children: [
            const DefiText('Odległość do najbliższego AED', variant: TextVariant.title),
            // The legend explains the map right under the title.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.s8,
              children: [
                _LegendRow(swatch: const _Swatch.covered(), text: 'Do ${formatDistance(thresholdM)} od AED'),
                _LegendRow(swatch: const _Swatch.gap(), text: 'Dalej niż ${formatDistance(thresholdM)}'),
              ],
            ),
          ],
        ),
        DefiChoiceGroup<CoverageScenario>(
          legend: 'Scenariusz',
          options: [for (final s in CoverageScenario.values) (value: s, label: s.label)],
          value: scenario,
          onChanged: (value) => coverage.setQuery(scenario: value),
        ),
        if (scenario == CoverageScenario.availableAt)
          Row(
            children: [
              Expanded(child: DefiText('Pora: ${live ? 'teraz' : formatWarsawTime(now)}')),
              DefiButton(
                variant: ButtonVariant.link,
                label: 'Zmień',
                onPressed: () => ref.read(aedsProvider.notifier).setTimePickerOpen(true),
              ),
            ],
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s8,
          children: [
            Text.rich(
              TextSpan(
                text: 'Promień: ',
                children: [TextSpan(text: formatDistance(radius.value), style: AppTextStyles.label)],
              ),
              style: AppTextStyles.body,
            ),
            DefiRangeSlider(
              label: 'Promień',
              min: coverageRadius.min,
              max: coverageRadius.max,
              step: coverageRadius.step,
              value: radius.value,
              valueText: formatDistance,
              onChanged: (value) => radius.value = value,
              minLabel: formatDistance(coverageRadius.min),
              maxLabel: formatDistance(coverageRadius.max),
            ),
          ],
        ),
        if (status == CoverageStatus.loading) const DefiLoadingText('Obliczamy zasięg…'),
        if (status == CoverageStatus.error)
          DefiNotice(
            tone: Tone.danger,
            title: 'Nie udało się obliczyć zasięgu.',
            actions: [DefiButton(label: 'Spróbuj ponownie', onPressed: coverage.load)],
          ),
        if (selected != null)
          DefiNotice(
            title: 'Wybrany obszar',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.s4,
              children: [
                Text(
                  selected.nearestDistanceM == null
                      ? 'Brak AED spełniającego warunki scenariusza.'
                      : 'Najbliższy AED: ${formatDistance(selected.nearestDistanceM!)} w linii prostej.',
                ),
                if (nearestAed != null)
                  DefiButton(
                    variant: ButtonVariant.link,
                    label: nearestAed.venueName,
                    onPressed: () => context.go(RoutePaths.aedPath(nearestAed.id)),
                  ),
              ],
            ),
          )
        else if (layer != null)
          const DefiText('Wybierz obszar na mapie, aby zobaczyć odległość.', tone: TextTone.secondary),
        const DefiText(
          'Odległość w linii prostej. Dane mogą być niepełne.',
          variant: TextVariant.meta,
          tone: TextTone.muted,
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.swatch, required this.text});

  final Widget swatch;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    spacing: AppSpacing.s12,
    children: [
      swatch,
      Flexible(child: DefiText(text)),
    ],
  );
}

/// Matches the map fills in features/map/lib/map_layers.dart: a white halo, or red hatching for gaps.
class _Swatch extends StatelessWidget {
  const _Swatch.covered() : hatched = false;
  const _Swatch.gap() : hatched = true;

  final bool hatched;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 24,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: hatched ? null : AppColors.surface,
        border: Border.all(color: hatched ? AppColors.danger : AppColors.borderControl),
        borderRadius: BorderRadius.circular(4),
      ),
      child: hatched ? const CustomPaint(painter: _HatchPainter()) : null,
    );
  }
}

/// repeating-linear-gradient(-45deg, danger 70% 0 2px, danger 18% 2px 6px).
class _HatchPainter extends CustomPainter {
  const _HatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.danger.withValues(alpha: 0.18));
    final stripe = Paint()
      ..color = AppColors.danger.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    // Stripes run at 45°, 6 apart across them (6 * √2 along each edge).
    final step = 6 * sqrt2;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), stripe);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => false;
}
