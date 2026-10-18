import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/lib/aed_status.dart';
import 'package:defiwawa/features/aeds/lib/availability.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';

/// Access status with the next known change in hours.
class AedStatusView extends StatelessWidget {
  const AedStatusView({super.key, required this.status});

  final AedStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppSpacing.s4,
      children: [
        DefiStatusText(status.label, tone: status.tone, icon: AppIconName.schedule),
        if (status.detail != null) DefiText(status.detail!),
      ],
    );
  }
}

/// Selectable AED row: walking time (rendered by the caller), name, address and access status.
class AedListItem extends StatelessWidget {
  const AedListItem({
    super.key,
    required this.aed,
    required this.status,
    required this.onTap,
    this.travel,
    this.selected = false,
  });

  final Aed aed;
  final AedStatus status;
  final VoidCallback onTap;
  final Widget? travel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // The row reaches 12 into the panel padding on both sides, like the web's negative margin.
    return LayoutBuilder(
      builder: (context, constraints) => OverflowBox(
        maxWidth: constraints.maxWidth + 2 * AppSpacing.s12,
        fit: OverflowBoxFit.deferToChild,
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.all(AppSpacing.s12 - 1),
              decoration: BoxDecoration(
                color: selected ? AppColors.accentSoft : null,
                // Flutter rounds only uniform borders; the divider row keeps square ends.
                borderRadius: selected ? AppRadius.control : null,
                border: selected
                    ? Border.all(color: AppColors.accent)
                    : const Border(
                        top: BorderSide(color: Colors.transparent),
                        left: BorderSide(color: Colors.transparent),
                        right: BorderSide(color: Colors.transparent),
                        bottom: BorderSide(color: AppColors.border),
                      ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.s4,
                children: [
                  ?travel,
                  DefiText(aed.venueName, variant: TextVariant.label),
                  DefiText(aed.address, tone: TextTone.secondary),
                  DefiStatusText(status.label, tone: status.tone, icon: AppIconName.schedule),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Photo of the cabinet's surroundings; nothing when the AED has none or it fails to load.
class AedPhoto extends StatelessWidget {
  const AedPhoto({super.key, required this.aed});

  final Aed aed;

  @override
  Widget build(BuildContext context) {
    final url = aed.photoUrl;
    if (url == null) return const SizedBox.shrink();
    // Half the photos are portrait: show the whole frame, letterboxed, so the cabinet is not cropped out.
    return ClipRRect(
      borderRadius: AppRadius.control,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SizedBox(
          width: double.infinity,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            semanticLabel: 'Miejsce defibrylatora: ${aed.venueName}',
            frameBuilder: (context, child, frame, _) =>
                frame == null ? child : ColoredBox(color: AppColors.unknownSoft, child: child),
            // A row can name a photo the bucket does not hold yet; hide it instead of a broken image.
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class AedHours extends StatelessWidget {
  const AedHours({super.key, required this.schedule, this.sourceHours, this.unverified});

  final Schedule schedule;
  final String? sourceHours;
  final Schedule? unverified;

  @override
  Widget build(BuildContext context) {
    final source = sourceHours != null
        ? DefiText('Wg źródła: $sourceHours', variant: TextVariant.meta, tone: TextTone.muted)
        : null;
    final draft = unverified;
    if (schedule is UnknownSchedule && draft != null && draft is! UnknownSchedule) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.s8,
        children: [
          const DefiText(
            'Niezweryfikowane. Godziny odczytane ze źródła, nie używamy ich do wskazywania dostępności.',
            tone: TextTone.secondary,
          ),
          AedHours(schedule: draft),
          ?source,
        ],
      );
    }
    return switch (schedule) {
      AlwaysOpen() => const DefiText('Całodobowo, 7 dni w tygodniu'),
      UnknownSchedule() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.s8,
        children: [
          const DefiText(
            'Brak informacji o godzinach, więc traktujemy AED jako niedostępny.',
            tone: TextTone.secondary,
          ),
          ?source,
        ],
      ),
      WeeklySchedule(:final days) => Column(
        children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.s16,
                children: [
                  DefiText(weekdayNames[i]),
                  Expanded(
                    child: Text(
                      switch (days[i]) {
                        null => 'niedostępny (brak danych)',
                        [] => 'zamknięte',
                        final intervals => intervals.map(formatInterval).join(', '),
                      },
                      textAlign: TextAlign.right,
                      style: AppTextStyles.body.copyWith(
                        color: days[i] == null ? AppColors.textSecondary : AppColors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    };
  }
}

// Basic life support with an AED, following the European Resuscitation Council guidelines.
const _usageSteps = [
  ('Sprawdź, czy oddycha', 'Jeśli poszkodowany nie reaguje i nie oddycha prawidłowo, działaj od razu.'),
  ('Zadzwoń pod 112', 'Włącz głośnik. Jeśli ktoś jest obok, niech przyniesie AED, a Ty zostań przy poszkodowanym.'),
  (
    'Uciskaj klatkę piersiową',
    'Środek klatki, na głębokość 5–6 cm, 100–120 razy na minutę. Nie przerywaj, dopóki AED nie jest gotowy.',
  ),
  ('Włącz AED', 'Otwórz pokrywę lub naciśnij przycisk zasilania. Urządzenie mówi, co robić: wykonuj jego polecenia.'),
  (
    'Naklej elektrody',
    'Na odsłoniętą, suchą klatkę: pod prawym obojczykiem i na lewym boku pod pachą, jak na rysunku.',
  ),
  (
    'Nie dotykaj podczas analizy',
    'Odsuń wszystkich. Jeśli AED zaleci wyładowanie, upewnij się, że nikt nie dotyka poszkodowanego, i naciśnij przycisk.',
  ),
  ('Wróć do uciskania', 'Zaraz po wyładowaniu lub komunikacie AED. Kontynuuj do przyjazdu pogotowia.'),
];

/// Emergency steps for using an AED, with a call button for 112.
class AedUsageGuide extends StatelessWidget {
  const AedUsageGuide({super.key, required this.onCall, this.withHeading = true});

  final VoidCallback onCall;

  /// Off inside a disclosure that already names the section.
  final bool withHeading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s12,
      children: [
        if (withHeading) const DefiText('Jak użyć defibrylatora', variant: TextVariant.heading),
        // Large tap target: on a phone this dials straight away.
        Semantics(
          button: true,
          child: GestureDetector(
            onTap: onCall,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12, horizontal: AppSpacing.s16),
              decoration: const BoxDecoration(color: AppColors.danger, borderRadius: AppRadius.control),
              child: DefaultTextStyle(
                style: AppTextStyles.label.copyWith(color: AppColors.surface),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: AppSpacing.s8,
                  children: [AppIcon(AppIconName.call), Text('Zadzwoń pod 112')],
                ),
              ),
            ),
          ),
        ),
        for (final (i, (title, detail)) in _usageSteps.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                child: Text(
                  '${i + 1}',
                  style: AppTextStyles.small(14, weight: FontWeight.w700).copyWith(color: AppColors.accent),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.label.copyWith(height: 28 / 16)),
                    DefiText(detail, tone: TextTone.secondary),
                  ],
                ),
              ),
            ],
          ),
        const DefiText(
          'Według wytycznych Europejskiej Rady Resuscytacji. AED nie wyładuje się, jeśli nie jest to potrzebne.',
          variant: TextVariant.meta,
          tone: TextTone.muted,
        ),
      ],
    );
  }
}

/// On-site directions to the cabinet: place, entrance, floor, access and photo.
class AedFindingGuide extends StatelessWidget {
  const AedFindingGuide({super.key, required this.aed});

  final Aed aed;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (AppIconName.locationOn, '${aed.venueName}, ${aed.address}'),
      (AppIconName.doorFront, aed.entrance ?? 'Źródło nie opisuje wejścia. Zapytaj obsługę lub ochronę budynku.'),
      (AppIconName.stairs, placementLabel(aed)),
      if (aed.publicAccess != PublicAccess.public)
        (AppIconName.lock, 'Dostęp może wymagać pomocy obsługi lub ochrony budynku.'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.s12,
      children: [
        const DefiText('Jak znaleźć urządzenie', variant: TextVariant.heading),
        AedPhoto(aed: aed),
        Column(
          spacing: AppSpacing.s8,
          children: [
            for (final (icon, text) in rows)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.s12,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AppIcon(icon, size: 20, color: AppColors.textSecondary),
                  ),
                  Expanded(child: DefiText(text)),
                ],
              ),
          ],
        ),
        const DefiText(
          'Szukaj zielonego znaku AED z sercem i błyskawicą. Szafka zwykle wisi przy wejściu, recepcji lub windach.',
          variant: TextVariant.meta,
          tone: TextTone.secondary,
        ),
      ],
    );
  }
}
