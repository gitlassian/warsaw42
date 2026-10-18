import 'package:flutter/foundation.dart';

import 'package:defiwawa/shared/geo/geo.dart';

/// Local Warsaw time "HH:MM"; "24:00" is allowed as an end. Start inclusive, end exclusive.
typedef Interval = (String start, String end);

/// PLAN.md §5. A day without data stays unknown; it never means closed.
sealed class Schedule {
  const Schedule();
}

final class AlwaysOpen extends Schedule {
  const AlwaysOpen();

  @override
  bool operator ==(Object other) => other is AlwaysOpen;

  @override
  int get hashCode => 1;
}

final class UnknownSchedule extends Schedule {
  const UnknownSchedule();

  @override
  bool operator ==(Object other) => other is UnknownSchedule;

  @override
  int get hashCode => 0;
}

final class WeeklySchedule extends Schedule {
  const WeeklySchedule(this.days);

  /// Index 0 = Monday; null = no data for that day, empty = closed.
  final List<List<Interval>?> days;

  @override
  bool operator ==(Object other) =>
      other is WeeklySchedule &&
      other.days.length == days.length &&
      Iterable.generate(days.length).every((i) => listEquals(days[i], other.days[i]));

  @override
  int get hashCode => Object.hashAll(days.map((d) => d == null ? null : Object.hashAll(d)));

  @override
  String toString() => 'WeeklySchedule($days)';
}

enum PublicAccess { public, restricted, unknown }

/// `osm`: found only in OpenStreetMap, not in the city register.
enum AedSource { city, osm }

/// Dataset the hours were read from; `cityOsm` means OpenStreetMap confirmed the city's days.
enum HoursSource { city, osm, cityOsm }

/// Device condition, independent of opening hours (ENDPOINTS.md §1).
enum OperationalStatus { unknown, confirmedUnavailable, confirmedOperational }

class Aed {
  const Aed({
    required this.id,
    required this.location,
    required this.venueName,
    required this.address,
    required this.entrance,
    required this.indoor,
    required this.floor,
    required this.publicAccess,
    required this.operationalStatus,
    required this.schedule,
    required this.sourceHours,
    this.photoUrl,
    this.unverifiedSchedule,
    this.source,
    this.hoursSource,
  });

  final String id;
  final LngLat location;
  final String venueName;
  final String address;

  /// Entrance and on-site instructions from the source.
  final String? entrance;
  final bool indoor;
  final int? floor;
  final PublicAccess publicAccess;
  final OperationalStatus operationalStatus;
  final Schedule schedule;

  /// Original access/hours wording from Warsaw Open Data.
  final String? sourceHours;

  /// Public photo of the cabinet (Supabase Storage).
  final String? photoUrl;

  /// Parsed from the source but not checked: shown with a warning, never used to say "open now".
  final Schedule? unverifiedSchedule;
  final AedSource? source;
  final HoursSource? hoursSource;
}

/// `app_data` key `status`.
class DataStatus {
  const DataStatus({required this.fetchedAt, required this.aedCount, required this.attribution});

  /// Last successful import; not a physical inspection of any device.
  final DateTime fetchedAt;
  final int aedCount;

  /// Source and licence line, e.g. "Dane: m.st. Warszawa, SCB (CC BY)".
  final String attribution;
}
