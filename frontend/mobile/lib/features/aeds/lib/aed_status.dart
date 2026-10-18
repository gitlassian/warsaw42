import 'package:design_system/design_system.dart';

import 'package:defiwawa/features/aeds/models/aed.dart';
import 'package:defiwawa/features/aeds/lib/availability.dart';

class AedStatus {
  const AedStatus({required this.tone, required this.icon, required this.label, this.detail, this.available = false});

  final Tone tone;
  final AppIconName icon;

  /// Short access status (DESIGN.md §3), e.g. "Dostępny do 18:00".
  final String label;

  /// Next known change when the label does not say it, e.g. "Otwarcie o 08:00".
  final String? detail;

  /// Open according to known hours and public: the only status shown as available.
  final bool available;
}

/// Access status at [at]. Device condition wins over hours; hours never confirm the device works.
AedStatus aedStatus(Aed aed, DateTime at) {
  if (aed.operationalStatus == OperationalStatus.confirmedUnavailable) {
    return const AedStatus(tone: Tone.danger, icon: AppIconName.error, label: 'AED niedostępny');
  }
  if (aed.publicAccess == PublicAccess.restricted) {
    return const AedStatus(tone: Tone.warning, icon: AppIconName.warning, label: 'Dostęp niepotwierdzony');
  }
  // No information means unavailable.
  if (aed.publicAccess == PublicAccess.unknown) {
    return const AedStatus(
      tone: Tone.neutral,
      icon: AppIconName.lock,
      label: 'Niedostępny',
      detail: 'Brak informacji o dostępie',
    );
  }
  return switch (evaluateHours(aed.schedule, at)) {
    HoursOpen(:final until) => AedStatus(
      tone: Tone.accent,
      icon: AppIconName.checkCircle,
      label: until != null ? 'Dostępny do $until' : 'Dostęp całodobowy',
      available: true,
    ),
    HoursClosed(:final opensAt) => AedStatus(
      tone: Tone.neutral,
      icon: AppIconName.lock,
      label: 'Teraz zamknięty',
      detail: opensAt != null ? 'Otwarcie o $opensAt' : null,
    ),
    HoursUnknown() => AedStatus(
      tone: Tone.neutral,
      icon: AppIconName.lock,
      label: 'Niedostępny',
      detail: _sourceHoursDetail(aed.sourceHours) ?? 'Brak informacji o godzinach',
    ),
  };
}

/// The source wording stays visible when it could not be turned into checked hours.
String? _sourceHoursDetail(String? text) {
  final t = text?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t == null || t.isEmpty) return null;
  return 'Wg źródła: ${t.length > 70 ? '${t.substring(0, 67)}…' : t}';
}

/// Indoor/outdoor placement with the floor when known.
String placementLabel(Aed aed) {
  final place = aed.indoor ? 'Wewnątrz budynku' : 'Na zewnątrz';
  final floor = aed.floor;
  if (floor == null) return place;
  return '$place, ${floor == 0
      ? 'parter'
      : floor > 0
      ? 'piętro $floor'
      : 'poziom $floor'}';
}

/// Coarse state used for the map filters; [aedStatus] has the full wording. No information means unavailable.
enum AedAvailability { available, unavailable }

AedAvailability aedAvailability(Aed aed, DateTime at) {
  if (aed.operationalStatus == OperationalStatus.confirmedUnavailable || aed.publicAccess != PublicAccess.public) {
    return AedAvailability.unavailable;
  }
  return evaluateHours(aed.schedule, at) is HoursOpen ? AedAvailability.available : AedAvailability.unavailable;
}

/// Groups the user wants to see. With none selected there is no filter and every AED is shown.
typedef AedFilters = ({bool available, bool unavailable});

bool passesFilters(Aed aed, DateTime at, AedFilters filters) {
  if (!filters.available && !filters.unavailable) return true;
  return switch (aedAvailability(aed, at)) {
    AedAvailability.available => filters.available,
    AedAvailability.unavailable => filters.unavailable,
  };
}
