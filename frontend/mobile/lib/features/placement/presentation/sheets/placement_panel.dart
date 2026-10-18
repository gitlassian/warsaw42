import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/lib/availability.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/map/lib/map_camera.dart';
import 'package:defiwawa/features/placement/models/placement.dart';
import 'package:defiwawa/features/placement/providers/placement_provider.dart';

/// Percentages as the web prints them: `22`, `21.2`.
String _pct(double value) => value == value.roundToDouble() ? '${value.toInt()}' : '$value';

String _zloty(int value) => '${formatCount(value)} zł';

/// "Gdzie dodać AED": the addresses that bring the most residents within reach of an open AED at the chosen time.
class PlacementPanel extends HookConsumerWidget {
  const PlacementPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlacementState(:status, :data, :mode, :count, :selected) = ref.watch(placementProvider);
    final placement = ref.read(placementProvider.notifier);
    final now = ref.watch(aedsProvider.select((s) => s.now));
    final live = ref.watch(aedsProvider.select((s) => s.live));
    final view = ref.watch(placementViewProvider);

    useEffect(() {
      Future.microtask(placement.load);
      return null;
    }, const []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s24,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s8,
          children: [
            DefiText('Gdzie dodać AED', variant: TextVariant.title),
            DefiText(
              'Miejsca, które dają najwięcej mieszkańców w zasięgu otwartego AED o wybranej porze.',
              tone: TextTone.secondary,
            ),
          ],
        ),
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
        DefiChoiceGroup<PlacementMode>(
          legend: 'Co pokazać',
          options: [for (final m in PlacementMode.values) (value: m, label: m.label)],
          value: mode,
          onChanged: placement.setMode,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s8,
          children: [
            Text.rich(
              TextSpan(
                text: 'Liczba punktów: ',
                children: [
                  TextSpan(
                    text: '$count',
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              style: AppTextStyles.body,
            ),
            DefiRangeSlider(
              label: 'Liczba punktów',
              min: 1,
              max: placementMaxSteps.toDouble(),
              step: 1,
              value: count.toDouble(),
              valueText: (v) => '${v.round()}',
              onChanged: (v) => placement.setCount(v.round()),
              minLabel: '1',
              maxLabel: '$placementMaxSteps',
            ),
          ],
        ),
        if (status == PlacementStatus.loading) const DefiLoadingText('Wczytujemy obliczenia…'),
        if (status == PlacementStatus.error)
          DefiNotice(
            tone: Tone.danger,
            title: 'Nie udało się wczytać obliczeń.',
            actions: [DefiButton(label: 'Spróbuj ponownie', onPressed: placement.load)],
          ),
        if (data != null && view != null) ...[
          _Summary(data: data, view: view, mode: mode, count: count),
          if (view.picks.isEmpty)
            const DefiText('O tej porze nie ma takich punktów.', tone: TextTone.secondary)
          else
            DefiDisclosure(
              title: 'Lista punktów (${view.picks.length})',
              last: true,
              children: [
                for (final pick in view.picks)
                  _PickItem(
                    pick: pick,
                    showAddress: mode == PlacementMode.convert,
                    selected: selected == pick.rank,
                    onTap: () {
                      placement.select(pick.rank);
                      mapCamera.focus(LngLat(pick.lng, pick.lat));
                    },
                  ),
              ],
            ),
          DefiText(
            'Zasięg w linii prostej (${formatDistance(data.radiusM)}). Mieszkańcy: spis GUS 2021 rozłożony na budynki '
            'mieszkalne Warszawy, to szacunek do ustalania priorytetów, nie projekt rozmieszczenia.',
            variant: TextVariant.meta,
            tone: TextTone.muted,
          ),
        ],
      ],
    );
  }
}

const _tabular = [FontFeature.tabularFigures()];

/// 13 px text keeps the web's 24 px line, so the pills and the 65+ row match it.
TextStyle _small(FontWeight weight) => AppTextStyles.small(13, weight: weight).copyWith(height: 24 / 13);

/// Residents within reach now and after the picks, as figures and a bar, then the facts behind them.
class _Summary extends StatelessWidget {
  const _Summary({required this.data, required this.view, required this.mode, required this.count});

  final PlacementData data;
  final PlacementView view;
  final PlacementMode mode;
  final int count;

  @override
  Widget build(BuildContext context) {
    final slot = view.slot;
    final hasPicks = view.picks.isNotEmpty;
    final pct = AppTextStyles.small(28, weight: FontWeight.w700).copyWith(height: 1, fontFeatures: _tabular);
    return Semantics(
      label: 'Podsumowanie',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: const BoxDecoration(color: AppColors.unknownSoft, borderRadius: AppRadius.control),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s12,
          children: [
            Text(
              'Mieszkańcy do ${formatDistance(data.radiusM)} od otwartego AED',
              style: _small(FontWeight.w600).copyWith(color: AppColors.textSecondary),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              spacing: AppSpacing.s8,
              children: [
                Text('${_pct(slot.coveredPct)}%', style: pct.copyWith(color: AppColors.textPrimary)),
                if (hasPicks) ...[
                  Semantics(
                    label: 'po zmianie',
                    excludeSemantics: true,
                    child: Text('→', style: AppTextStyles.small(20).copyWith(color: AppColors.textMuted)),
                  ),
                  Text('${_pct(view.coveredPctAfter)}%', style: pct.copyWith(color: AppColors.accent)),
                  _Pill(
                    '+${_pct(view.gainPct)} p.p.',
                    color: AppColors.accent,
                    background: AppColors.accentSoft,
                    weight: FontWeight.w700,
                  ),
                ],
              ],
            ),
            // Within reach now, and what the picks add.
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: AppRadius.pill,
                child: Container(
                  height: 8,
                  color: AppColors.border,
                  child: LayoutBuilder(
                    builder: (context, box) => Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: box.maxWidth * (slot.coveredPct / 100).clamp(0, 1),
                          child: const ColoredBox(color: AppColors.textSecondary),
                        ),
                        SizedBox(
                          width: box.maxWidth * ((view.coveredPctAfter - slot.coveredPct) / 100).clamp(0, 1),
                          child: const ColoredBox(color: AppColors.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.only(top: AppSpacing.s12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.s8,
                children: [
                  _Fact('Otwarte AED o tej porze', formatCount(slot.openAeds)),
                  // The 65+ line sits closer to the total it belongs to.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.s4,
                    children: [
                      _Fact('Bez AED w zasięgu', '${formatCount(slot.uncovered)} osób'),
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.s12),
                        child: _Fact('w tym w wieku 65+', formatCount(slot.uncovered65), small: true),
                      ),
                    ],
                  ),
                  if (hasPicks)
                    _Fact(
                      'Zyskuje dostęp ($count ${mode == PlacementMode.newSites ? 'nowych punktów' : 'udostępnionych AED'})',
                      '+${formatCount(view.gainPeople)} osób',
                      highlight: true,
                    ),
                  if (mode == PlacementMode.newSites) _Fact('Szacunkowy koszt', _zloty(count * data.costPerAedPln)),
                ],
              ),
            ),
            DefiText(
              mode == PlacementMode.newSites
                  ? '$count × ${_zloty(data.costPerAedPln)} (${data.costBasis}).'
                  : 'Bez zakupu: wystarczy udostępnić istniejące urządzenie całą dobę, np. szafka na zewnątrz budynku.',
              variant: TextVariant.meta,
              tone: TextTone.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A label and its figure at the far end of the row; [highlight] puts both in green.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.small = false, this.highlight = false});

  final String label;
  final String value;
  final bool small;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final style = small ? _small(FontWeight.w400) : AppTextStyles.body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: AppSpacing.s12,
      children: [
        Expanded(
          child: Text(
            label,
            style: style.copyWith(
              color: highlight ? AppColors.accent : AppColors.textSecondary,
              fontWeight: highlight ? FontWeight.w700 : null,
            ),
          ),
        ),
        Text(
          value,
          softWrap: false,
          style: style.copyWith(
            color: highlight ? AppColors.accent : AppColors.textPrimary,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
            fontFeatures: _tabular,
          ),
        ),
      ],
    );
  }
}

/// Small rounded tag: the gain in percentage points, the 65+ residents.
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color, required this.background, this.weight = FontWeight.w600});

  final String text;
  final Color color;
  final Color background;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: AppRadius.pill),
      child: Text(text, style: _small(weight).copyWith(color: color)),
    );
  }
}

/// A ranked site: green rank disc, the address (and the AED's own address when converting), the residents it adds.
class _PickItem extends StatelessWidget {
  const _PickItem({required this.pick, required this.showAddress, required this.selected, required this.onTap});

  final PlacementPick pick;
  final bool showAddress;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : AppColors.surface,
            border: Border.all(color: selected ? AppColors.accent : AppColors.border),
            borderRadius: AppRadius.control,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.s12,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: Text(
                  '${pick.rank}',
                  style: AppTextStyles.small(14, weight: FontWeight.w700).copyWith(color: AppColors.surface),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.s4,
                  children: [
                    Text(pick.title, style: AppTextStyles.label),
                    if (showAddress)
                      Text(pick.address, style: _small(FontWeight.w400).copyWith(color: AppColors.textSecondary)),
                    Wrap(
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '+${formatCount(pick.gain)} osób',
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontFeatures: _tabular,
                          ),
                        ),
                        _Pill(
                          '65+: ${formatCount(pick.gain65)}',
                          color: AppColors.textSecondary,
                          background: AppColors.unknownSoft,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
