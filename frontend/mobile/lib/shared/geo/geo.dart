import 'dart:math';

import 'package:defiwawa/shared/geo/warsaw_boundary.dart';

class LngLat {
  const LngLat(this.lng, this.lat);

  final double lng;
  final double lat;

  @override
  bool operator ==(Object other) => other is LngLat && other.lng == lng && other.lat == lat;

  @override
  int get hashCode => Object.hash(lng, lat);

  @override
  String toString() => 'LngLat($lng, $lat)';
}

const warsawCenter = LngLat(21.0122, 52.2297);

/// Camera limit: the city bbox with a small margin (PLAN.md §1).
const warsawSouthWest = LngLat(20.72, 52.02);
const warsawNorthEast = LngLat(21.4, 52.44);

/// Ray casting against the city boundary; origins outside are rejected, never clamped.
bool isInsideWarsaw(LngLat p) {
  var inside = false;
  for (var i = 0, j = warsawBoundary.length - 1; i < warsawBoundary.length; j = i++) {
    final (xi, yi) = warsawBoundary[i];
    final (xj, yj) = warsawBoundary[j];
    if ((yi > p.lat) != (yj > p.lat) && p.lng < (xj - xi) * (p.lat - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

const _earthRadiusM = 6371000.0;
double _toRad(double deg) => deg * pi / 180;

/// Great-circle distance in meters.
double distanceMeters(LngLat a, LngLat b) {
  final dLat = _toRad(b.lat - a.lat);
  final dLng = _toRad(b.lng - a.lng);
  final h = pow(sin(dLat / 2), 2) + cos(_toRad(a.lat)) * cos(_toRad(b.lat)) * pow(sin(dLng / 2), 2);
  return 2 * _earthRadiusM * asin(sqrt(h));
}

/// GeoJSON polygon approximating a circle, for the GPS accuracy area.
Map<String, Object> circlePolygon(LngLat center, double radiusM, {int steps = 48}) {
  final dLat = radiusM / 111320;
  final dLng = dLat / cos(_toRad(center.lat));
  final ring = [
    for (var i = 0; i <= steps; i++)
      [center.lng + dLng * cos(i / steps * 2 * pi), center.lat + dLat * sin(i / steps * 2 * pi)],
  ];
  return {
    'type': 'Polygon',
    'coordinates': [ring],
  };
}
