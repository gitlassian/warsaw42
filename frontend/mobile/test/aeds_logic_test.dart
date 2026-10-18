import 'package:defiwawa/features/aeds/lib/aed_status.dart';
import 'package:defiwawa/features/aeds/lib/availability.dart';
import 'package:defiwawa/features/aeds/lib/from_row.dart';
import 'package:defiwawa/features/aeds/lib/view_time.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';
import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/shared/lib/format.dart';
import 'package:flutter_test/flutter_test.dart';

// Ports of the web tests (availability, aedAvailability, fromRow, viewTime).

// The PLAN.md §5 example: Mon 08–18, Tue–Fri 08–16, weekend not stated.
const office = WeeklySchedule([
  [('08:00', '18:00')],
  [('08:00', '16:00')],
  [('08:00', '16:00')],
  [('08:00', '16:00')],
  [('08:00', '16:00')],
  null,
  null,
]);

DateTime at(String iso) => DateTime.parse(iso);
DateTime monday(String hhmm) => at('2026-10-19T$hhmm:00+02:00');

const base = Aed(
  id: '1',
  location: LngLat(21, 52.2),
  venueName: 'x',
  address: 'y',
  entrance: null,
  indoor: true,
  floor: null,
  publicAccess: PublicAccess.public,
  operationalStatus: OperationalStatus.unknown,
  schedule: UnknownSchedule(),
  sourceHours: null,
);

Aed withSchedule(Schedule schedule, {PublicAccess access = PublicAccess.public, OperationalStatus? status}) => Aed(
  id: base.id,
  location: base.location,
  venueName: base.venueName,
  address: base.address,
  entrance: null,
  indoor: true,
  floor: null,
  publicAccess: access,
  operationalStatus: status ?? OperationalStatus.unknown,
  schedule: schedule,
  sourceHours: null,
);

void main() {
  test('open with closing time', () {
    expect(evaluateHours(office, monday('10:00')), isA<HoursOpen>().having((h) => h.until, 'until', '18:00'));
  });

  test('closed before and after hours, with the next opening the same day', () {
    expect(evaluateHours(office, monday('07:00')), isA<HoursClosed>().having((h) => h.opensAt, 'opensAt', '08:00'));
    expect(evaluateHours(office, monday('18:00')), isA<HoursClosed>().having((h) => h.opensAt, 'opensAt', null));
  });

  test('omitted weekend stays unknown; 24/7 is open around the clock', () {
    expect(evaluateHours(office, at('2026-10-17T12:00:00+02:00')), isA<HoursUnknown>());
    expect(evaluateHours(const AlwaysOpen(), DateTime.now()), isA<HoursOpen>().having((h) => h.until, 'until', null));
  });

  test('evaluates in Warsaw time, not UTC, across the DST switch', () {
    // 06:30 UTC on Monday = 08:30 in Warsaw (CEST).
    expect(evaluateHours(office, at('2026-10-19T06:30:00Z')), isA<HoursOpen>());
    // 07:30 UTC on Monday 26.10 = 08:30 in Warsaw (CET, after the clocks went back).
    expect(evaluateHours(office, at('2026-10-26T07:30:00Z')), isA<HoursOpen>());
    expect(evaluateHours(office, at('2026-10-26T06:30:00Z')), isA<HoursClosed>());
  });

  test('open, closed, and unknown hours (no information means unavailable)', () {
    final o = withSchedule(office);
    expect(aedAvailability(o, monday('10:00')), AedAvailability.available);
    expect(aedAvailability(o, monday('20:00')), AedAvailability.unavailable);
    expect(aedAvailability(base, monday('10:00')), AedAvailability.unavailable);
    expect(aedAvailability(withSchedule(const AlwaysOpen()), monday('03:00')), AedAvailability.available);
    expect(
      aedAvailability(withSchedule(office, status: OperationalStatus.confirmedUnavailable), monday('10:00')),
      AedAvailability.unavailable,
    );
    expect(
      aedAvailability(withSchedule(office, access: PublicAccess.restricted), monday('10:00')),
      AedAvailability.unavailable,
    );
  });

  test('selected groups are shown, and no selection shows everything', () {
    const none = (available: false, unavailable: false);
    final o = withSchedule(office);
    expect(passesFilters(base, monday('10:00'), none), true);
    expect(passesFilters(o, monday('10:00'), (available: true, unavailable: false)), true);
    expect(passesFilters(o, monday('20:00'), (available: true, unavailable: false)), false);
    expect(passesFilters(base, monday('10:00'), (available: false, unavailable: true)), true);
  });

  test('status labels and placement', () {
    expect(aedStatus(withSchedule(office), monday('10:00')).label, 'Dostępny do 18:00');
    expect(aedStatus(withSchedule(office), monday('07:00')).detail, 'Otwarcie o 08:00');
    expect(aedStatus(base, monday('10:00')).detail, 'Brak informacji o godzinach');
  });

  final row = <String, dynamic>{
    'id': 'b1',
    'object_name': 'Urząd',
    'full_address': 'Rakowiecka 25/27, 02-517 Warszawa',
    'lon': 21.01,
    'lat': 52.2,
    'in_building': true,
    'floor': 0,
    'access_instructions': null,
    'public_access': 'public',
    'operational_status': 'unknown',
    'hours_text': 'Pn 8-18',
    'hours_status': 'scheduled',
    'hours_verified': true,
    'hours': <String, dynamic>{},
    'photo_path': '622.webp',
    'source': 'city',
    'hours_source': 'city_osm',
  };

  test('minutes become HH:MM and ISO weekdays become indexes from Monday', () {
    final schedule = scheduleFromRow({
      ...row,
      'hours': {
        'weekly': {
          '1': {
            'state': 'open_intervals',
            'intervals': [
              [480, 1080],
            ],
          },
          '3': {
            'state': 'open_intervals',
            'intervals': [
              [0, 1440],
            ],
          },
          '6': {'state': 'closed', 'intervals': []},
        },
      },
    });
    expect(
      schedule,
      const WeeklySchedule([
        [('08:00', '18:00')],
        null,
        [('00:00', '24:00')],
        null,
        null,
        [],
        null,
      ]),
    );
  });

  test('unverified or unparsed hours are unknown, 24/7 is always open', () {
    expect(scheduleFromRow({...row, 'hours_verified': false}), const UnknownSchedule());
    expect(scheduleFromRow({...row, 'hours_status': 'unknown'}), const UnknownSchedule());
    expect(scheduleFromRow({...row, 'hours_status': '24/7'}), const AlwaysOpen());
    expect(
      scheduleFromRow({
        ...row,
        'hours': {'weekly': {}},
      }),
      const UnknownSchedule(),
    );
  });

  test('row maps to the Aed model with a photo link', () {
    final aed = aedFromRow(row, (f) => 'https://x/$f');
    expect(aed.location, const LngLat(21.01, 52.2));
    expect(aed.photoUrl, 'https://x/622.webp');
    expect(aed.hoursSource, HoursSource.cityOsm);
    expect(aed.unverifiedSchedule, isNull);
    expect(aedFromRow({...row, 'photo_path': null}, (f) => f).photoUrl, isNull);
  });

  final satAfternoon = at('2026-10-17T15:00:00+02:00');

  test('time picker: same weekday means today, other weekdays the next such day', () {
    expect(nextWarsawWeekday(5, 3 * 60, satAfternoon), at('2026-10-17T03:00:00+02:00'));
    expect(nextWarsawWeekday(0, 10 * 60, satAfternoon), at('2026-10-19T10:00:00+02:00'));
    expect(nextWarsawWeekday(4, 23 * 60 + 45, satAfternoon), at('2026-10-23T23:45:00+02:00'));
  });

  test('time picker: winter offset after 25.10.2026, Warsaw date picks the day', () {
    expect(nextWarsawWeekday(0, 10 * 60, at('2026-10-25T12:00:00+01:00')), at('2026-10-26T10:00:00+01:00'));
    // 23:30 UTC on Saturday is already 01:30 on Sunday in Warsaw.
    expect(nextWarsawWeekday(6, 8 * 60, at('2026-10-17T23:30:00Z')), at('2026-10-18T08:00:00+02:00'));
  });

  test('Polish formats', () {
    expect(formatDistance(284), '280 m');
    expect(formatDistance(1234), '1,2 km');
    expect(formatDistance(2000), '2 km');
    expect(formatDuration(20), '1 min');
    expect(formatDateTime(at('2026-10-17T08:00:00Z')), '17.10.2026, 10:00');
    expect(formatWarsawTime(monday('10:00')), 'Poniedziałek, 10:00');
  });
}
