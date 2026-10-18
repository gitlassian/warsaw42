import 'dart:math';

import 'package:clipper2/clipper2.dart';

import 'package:defiwawa/features/coverage/models/coverage.dart';

const _mPerDegLat = 111320.0;
const _circleSteps = 32;

/// Degrees to integer coordinates for Clipper2 (about 1 cm).
const _scale = 1e7;

Path64 _circle(Site site, double radiusM) {
  final dLat = radiusM / _mPerDegLat;
  final dLng = dLat / cos(site.lat * pi / 180);
  return [
    for (var i = 0; i < _circleSteps; i++)
      Point64.fromDouble(
        site.lng + dLng * cos(i / _circleSteps * 2 * pi),
        site.lat + dLat * sin(i / _circleSteps * 2 * pi),
        scale: _scale,
      ),
  ];
}

List<List<double>> _ring(Path64 path) => [
  for (final p in [...path, path.first]) [p.x / _scale, p.y / _scale],
];

/// GeoJSON MultiPolygon coordinates: each outer ring followed by its holes, islands as their own polygons.
List<List<List<List<double>>>> _multiPolygon(PolyPath64 tree) {
  final polygons = <List<List<List<double>>>>[];
  void outer(PolyPath64 node) {
    polygons.add([_ring(node.polygon!), for (final hole in node.children) _ring(hole.polygon!)]);
    for (final hole in node.children) {
      hole.children.forEach(outer);
    }
  }

  tree.children.forEach(outer);
  return polygons;
}

List<Map<String, Object>> _area(CoverageKind kind, PolyPath64 tree) {
  final coordinates = _multiPolygon(tree);
  if (coordinates.isEmpty) return const [];
  return [
    {
      'type': 'Feature',
      'properties': {'kind': kind.name},
      'geometry': {'type': 'MultiPolygon', 'coordinates': coordinates},
    },
  ];
}

/// Where an AED is within reach and where none is. AEDs without information are not eligible (no data means unavailable).
/// - covered: the union of circles of [radiusM] around the eligible AEDs (drawn as white halos)
/// - gap: the rest of the city (drawn red)
List<Map<String, Object>> coverageAreas(List<(double, double)> boundary, List<Site> eligible, double radiusM) {
  final city = [for (final (lng, lat) in boundary) Point64.fromDouble(lng, lat, scale: _scale)];
  final circles = [for (final site in eligible) _circle(site, radiusM)];
  final covered = Clipper.booleanOpPolyTree(clipType: ClipType.union, subject: circles, fillRule: FillRule.nonZero);
  final gap = Clipper.booleanOpPolyTree(
    clipType: ClipType.difference,
    subject: [city],
    clip: Paths64Ext.fromPolyTree(covered),
    fillRule: FillRule.nonZero,
  );
  return [..._area(CoverageKind.gap, gap), ..._area(CoverageKind.covered, covered)];
}

/// Straight-line distance in meters from a point to the nearest site (equirectangular, fine at city scale).
({Site site, double distanceM})? nearestSite(double lng, double lat, List<Site> sites) {
  final mPerDegLng = _mPerDegLat * cos(lat * pi / 180);
  ({Site site, double distanceM})? best;
  for (final site in sites) {
    final dx = (site.lng - lng) * mPerDegLng, dy = (site.lat - lat) * _mPerDegLat;
    final distanceM = sqrt(dx * dx + dy * dy);
    if (best == null || distanceM < best.distanceM) best = (site: site, distanceM: distanceM);
  }
  return best;
}
