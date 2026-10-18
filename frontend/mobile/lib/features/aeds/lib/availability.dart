import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';

// Shared hours evaluator (PLAN.md §5–6), a port of the web's; the backend evaluator is authoritative online.

sealed class HoursEvaluation {
  const HoursEvaluation();
}

/// [until] null = around the clock.
final class HoursOpen extends HoursEvaluation {
  const HoursOpen(this.until);
  final String? until;
}

/// [opensAt]: next opening later the same day.
final class HoursClosed extends HoursEvaluation {
  const HoursClosed(this.opensAt);
  final String? opensAt;
}

final class HoursUnknown extends HoursEvaluation {
  const HoursUnknown();
}

/// Weekday (0 = Monday) and minutes since local midnight in Warsaw.
({int day, int minutes}) warsawClock(DateTime at) {
  final wall = warsawWall(at);
  return (day: wall.weekday - 1, minutes: wall.hour * 60 + wall.minute);
}

/// "Poniedziałek, 10:00" in Warsaw time, for the map time preview.
String formatWarsawTime(DateTime at) {
  final (:day, :minutes) = warsawClock(at);
  return '${weekdayNames[day]}, ${clockText(minutes)}';
}

int _toMinutes(String hhmm) {
  final [h, m] = hhmm.split(':').map(int.parse).toList();
  return h * 60 + m;
}

HoursEvaluation evaluateHours(Schedule schedule, DateTime at) {
  switch (schedule) {
    case AlwaysOpen():
      return const HoursOpen(null);
    case UnknownSchedule():
      return const HoursUnknown();
    case WeeklySchedule(:final days):
      final (:day, :minutes) = warsawClock(at);
      final intervals = days[day];
      if (intervals == null) return const HoursUnknown();
      for (final (start, end) in intervals) {
        if (_toMinutes(start) <= minutes && minutes < _toMinutes(end)) return HoursOpen(end);
      }
      for (final (start, _) in intervals) {
        if (_toMinutes(start) > minutes) return HoursClosed(start);
      }
      return const HoursClosed(null);
  }
}

String formatInterval(Interval interval) => '${interval.$1}–${interval.$2}';
