import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';

/// Columns of `public.aeds` (ENDPOINTS.md "AED data") read by [aedFromRow].
const aedColumns =
    'id,object_name,full_address,lon,lat,in_building,floor,access_instructions,public_access,operational_status,hours_text,hours_status,hours_verified,hours,photo_path,source,hours_source';

/// Unverified hours stay unknown, and so does any weekday the database does not state (never "closed").
Schedule scheduleFromRow(Map<String, dynamic> row) =>
    row['hours_verified'] == true ? parsedSchedule(row) : const UnknownSchedule();

/// The stored intervals whether or not they were verified; unknown when nothing was parsed.
Schedule parsedSchedule(Map<String, dynamic> row) {
  if (row['hours_status'] == '24/7') return const AlwaysOpen();
  if (row['hours_status'] != 'scheduled') return const UnknownSchedule();
  final weekly = (row['hours'] as Map?)?['weekly'] as Map? ?? const {};
  // Database weekdays are ISO 1 (Monday) to 7; the model's index 0 is Monday.
  final days = List<List<Interval>?>.generate(7, (i) {
    final day = weekly['${i + 1}'] as Map?;
    // Minutes after midnight; 1440 becomes "24:00", which the evaluator accepts as an end.
    if (day?['state'] == 'open_intervals') {
      return [
        for (final [start, end] in (day!['intervals'] as List).cast<List>())
          (clockText((start as num).toInt()), clockText((end as num).toInt())),
      ];
    }
    return day?['state'] == 'closed' ? <Interval>[] : null;
  });
  return days.every((d) => d == null) ? const UnknownSchedule() : WeeklySchedule(days);
}

T? _enum<T extends Enum>(List<T> values, Object? name) {
  final camel = (name as String?)?.replaceAllMapped(RegExp(r'_(\w)'), (m) => m[1]!.toUpperCase());
  return values.where((v) => v.name == camel).firstOrNull;
}

Aed aedFromRow(Map<String, dynamic> row, String Function(String file) photoUrl) {
  final verified = row['hours_verified'] == true;
  final photo = row['photo_path'] as String?;
  return Aed(
    id: row['id'].toString(),
    location: LngLat((row['lon'] as num).toDouble(), (row['lat'] as num).toDouble()),
    venueName: row['object_name'] as String,
    address: row['full_address'] as String,
    entrance: row['access_instructions'] as String?,
    indoor: row['in_building'] == true,
    floor: (row['floor'] as num?)?.toInt(),
    publicAccess: _enum(PublicAccess.values, row['public_access']) ?? PublicAccess.unknown,
    operationalStatus: _enum(OperationalStatus.values, row['operational_status']) ?? OperationalStatus.unknown,
    schedule: scheduleFromRow(row),
    unverifiedSchedule: verified ? null : parsedSchedule(row),
    sourceHours: row['hours_text'] as String?,
    photoUrl: photo != null ? photoUrl(photo) : null,
    source: _enum(AedSource.values, row['source']),
    hoursSource: _enum(HoursSource.values, row['hours_source']),
  );
}
