import 'dart:math';

import 'package:design_system/design_system.dart';

import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';

/// Where the walker is: meters walked along the route line and meters away from it.
typedef RouteProgress = ({double alongM, double offRouteM});

/// Route line measured once, with each step's maneuver placed on it.
class RoutePlan {
  const RoutePlan({
    required this.coordinates,
    required this.cumulativeM,
    required this.totalM,
    required this.stepAlongM,
  });

  final List<List<double>> coordinates;

  /// Meters from the start to each coordinate.
  final List<double> cumulativeM;
  final double totalM;

  /// Meters from the start to each step's maneuver, never decreasing.
  final List<double> stepAlongM;
}

/// A maneuver this close behind the walker counts as done, so GPS jitter does not repeat it.
const _passedM = 8;

/// The destination counts as reached within this distance.
const _arrivedM = 20;

/// Farther than this from the line (and beyond the GPS accuracy) the walker is off the route.
const offRouteM = 40.0;

const _mPerDeg = 111320.0;

// Equirectangular meters around `ref`: accurate enough for city-scale walking routes.
(double, double) _toXY(double lng, double lat, LngLat ref) =>
    ((lng - ref.lng) * _mPerDeg * cos(ref.lat * pi / 180), (lat - ref.lat) * _mPerDeg);

double _segmentLength(List<double> a, List<double> b) {
  final (x, y) = _toXY(b[0], b[1], LngLat(a[0], a[1]));
  return sqrt(x * x + y * y);
}

typedef _Hit = ({double distanceM, double alongM, int segment});

/// Closest point of segment [i] to [p]: distance to it and meters along the route.
_Hit _project(List<List<double>> c, List<double> cumulative, int i, LngLat p) {
  final a = LngLat(c[i][0], c[i][1]);
  final (bx, by) = _toXY(c[i + 1][0], c[i + 1][1], a);
  final (px, py) = _toXY(p.lng, p.lat, a);
  final len2 = bx * bx + by * by;
  final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
  final dx = px - t * bx, dy = py - t * by;
  return (
    distanceM: sqrt(dx * dx + dy * dy),
    alongM: cumulative[i] + t * (cumulative[i + 1] - cumulative[i]),
    segment: i,
  );
}

_Hit _nearest(List<List<double>> c, List<double> cumulative, LngLat p, [int fromSegment = 0]) {
  _Hit best = (distanceM: double.infinity, alongM: 0, segment: fromSegment);
  for (var i = fromSegment; i < c.length - 1; i++) {
    final hit = _project(c, cumulative, i, p);
    if (hit.distanceM < best.distanceM) best = hit;
  }
  return best;
}

RoutePlan planRoute(List<List<double>> coordinates, List<RouteStep> steps) {
  final cumulative = [0.0];
  for (var i = 1; i < coordinates.length; i++) {
    cumulative.add(cumulative[i - 1] + _segmentLength(coordinates[i - 1], coordinates[i]));
  }
  // Steps come in walking order, so each search starts at the previous step's segment (routes may loop back).
  var segment = 0;
  final stepAlongM = <double>[];
  for (final step in steps) {
    if (coordinates.length < 2) {
      stepAlongM.add(0);
      continue;
    }
    final hit = _nearest(coordinates, cumulative, step.location, segment);
    segment = hit.segment;
    stepAlongM.add(hit.alongM);
  }
  return RoutePlan(coordinates: coordinates, cumulativeM: cumulative, totalM: cumulative.last, stepAlongM: stepAlongM);
}

RouteProgress locateOnRoute(RoutePlan plan, LngLat position) {
  if (plan.coordinates.length < 2) return (alongM: 0, offRouteM: double.infinity);
  final hit = _nearest(plan.coordinates, plan.cumulativeM, position);
  return (alongM: hit.alongM, offRouteM: hit.distanceM);
}

/// Index of the next maneuver ahead of the walker; the last step ("arrive") once all others are done.
int upcomingStep(RoutePlan plan, double alongM) {
  final last = plan.stepAlongM.length - 1;
  for (var i = 1; i < last; i++) {
    if (plan.stepAlongM[i] > alongM + _passedM) return i;
  }
  return max(0, last);
}

bool isOffRoute(RouteProgress progress, [double accuracyM = 0]) => progress.offRouteM > max(offRouteM, accuracyM);

bool hasArrived(RoutePlan plan, RouteProgress progress) =>
    plan.totalM - progress.alongM <= _arrivedM && progress.offRouteM <= offRouteM;

/// Point [alongM] meters from the start of the route line, clamped to its ends.
LngLat pointAlong(RoutePlan plan, double alongM) {
  final c = plan.coordinates, m = plan.cumulativeM;
  if (c.isEmpty) return const LngLat(0, 0);
  if (c.length == 1) return LngLat(c[0][0], c[0][1]);
  final target = alongM.clamp(0.0, plan.totalM);
  var i = 0;
  while (i < c.length - 2 && m[i + 1] < target) {
    i++;
  }
  final length = m[i + 1] - m[i];
  final t = length == 0 ? 0.0 : (target - m[i]) / length;
  return LngLat(c[i][0] + t * (c[i + 1][0] - c[i][0]), c[i][1] + t * (c[i + 1][1] - c[i][1]));
}

/// Look-ahead for the heading: smooths small zigzags of the path and GPS noise.
const _headingAheadM = 25;

/// Walking direction at [alongM], in degrees clockwise from north, for a heading-up map.
/// Taken from the route line rather than the GPS heading, which is unreliable at walking speed.
double headingAt(RoutePlan plan, double alongM) {
  final from = pointAlong(plan, min(alongM, plan.totalM - 1));
  final to = pointAlong(plan, alongM + _headingAheadM);
  final (x, y) = _toXY(to.lng, to.lat, from);
  if (x == 0 && y == 0) return 0;
  return (atan2(x, y) * 180 / pi + 360) % 360;
}

const _turns = {
  'left': AppIconName.turnLeft,
  'right': AppIconName.turnRight,
  'slight left': AppIconName.turnSlightLeft,
  'slight right': AppIconName.turnSlightRight,
  'sharp left': AppIconName.turnSharpLeft,
  'sharp right': AppIconName.turnSharpRight,
  'uturn': AppIconName.uTurnLeft,
  'straight': AppIconName.straight,
};

/// Arrow for a Mapbox maneuver, like the Google Maps direction banner.
AppIconName maneuverIcon(RouteStep step) {
  final modifier = step.maneuverModifier;
  final leftish = modifier?.contains('left') ?? false;
  return switch (step.maneuverType) {
    'arrive' => AppIconName.aed,
    'depart' => AppIconName.navigation,
    'roundabout' ||
    'rotary' ||
    'roundabout turn' ||
    'exit roundabout' ||
    'exit rotary' => leftish ? AppIconName.roundaboutLeft : AppIconName.roundaboutRight,
    'fork' => leftish ? AppIconName.forkLeft : AppIconName.forkRight,
    _ => _turns[modifier] ?? AppIconName.straight,
  };
}
