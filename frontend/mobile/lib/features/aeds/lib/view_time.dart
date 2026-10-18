import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/lib/availability.dart';

/// Time picker for the map: the next instant (today included) at which the Warsaw wall clock shows
/// weekday [day] (0 = Monday) and [minutes] since midnight.
DateTime nextWarsawWeekday(int day, int minutes, DateTime from) {
  final today = warsawClock(from).day;
  final wall = warsawWall(from);
  final target = DateTime.utc(wall.year, wall.month, wall.day + (day - today + 7) % 7);
  return warsawInstant(target.year, target.month, target.day, minutes);
}
