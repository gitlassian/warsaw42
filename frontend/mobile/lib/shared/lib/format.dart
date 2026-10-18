// Polish formats in Europe/Warsaw time (DESIGN.md §8): 17.10.2026, 14:30 · 280 m · 1,2 km.

import 'dart:math';

/// 0 = Monday, matching ISO weekday order.
const weekdayNames = ['Poniedziałek', 'Wtorek', 'Środa', 'Czwartek', 'Piątek', 'Sobota', 'Niedziela'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "HH:MM" from minutes after midnight.
String clockText(int minutes) => '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';

/// UTC offset of Warsaw: CEST (+2) from the last Sunday of March to the last Sunday of October, 01:00 UTC.
// shortcut: the EU daylight-saving rule is built in, not a tz database; update it if the EU drops the clock change.
Duration warsawOffset(DateTime at) {
  final utc = at.toUtc();
  DateTime lastSunday(int month) {
    final lastDay = DateTime.utc(utc.year, month + 1, 0, 1);
    return lastDay.subtract(Duration(days: lastDay.weekday % 7));
  }

  final summer = !utc.isBefore(lastSunday(3)) && utc.isBefore(lastSunday(10));
  return Duration(hours: summer ? 2 : 1);
}

/// The Warsaw wall clock at [at], as a UTC DateTime whose fields read as Warsaw time.
DateTime warsawWall(DateTime at) => at.toUtc().add(warsawOffset(at));

/// The instant at which the Warsaw wall clock reads [year]-[month]-[day] plus [minutes]; settled in two passes around DST changes.
DateTime warsawInstant(int year, int month, int day, int minutes) {
  final wall = DateTime.utc(year, month, day, 0, minutes);
  final first = wall.subtract(warsawOffset(wall));
  return wall.subtract(warsawOffset(first));
}

/// 17.10.2026, 14:30
String formatDateTime(DateTime at) {
  final w = warsawWall(at);
  return '${_two(w.day)}.${_two(w.month)}.${w.year}, ${_two(w.hour)}:${_two(w.minute)}';
}

/// 14:30
String formatClock(DateTime at) {
  final w = warsawWall(at);
  return '${_two(w.hour)}:${_two(w.minute)}';
}

String formatDuration(num seconds) => '${max(1, (seconds / 60).round())} min';

String formatDistance(num meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  final km = (meters / 100).round() / 10;
  final text = km == km.roundToDouble() ? km.toInt().toString() : km.toStringAsFixed(1).replaceAll('.', ',');
  return '$text km';
}

/// Whole numbers as `Intl.NumberFormat('pl-PL')`: thousands split by a no-break space from five digits on.
String formatCount(int n) => n < 10000 ? '$n' : '$n'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '\u00A0');
