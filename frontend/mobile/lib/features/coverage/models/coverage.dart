/// GET /coverage scenarios (ENDPOINTS.md §5).
enum CoverageScenario {
  allPublic('Wszystkie publiczne'),
  availableAt('Dostępne o tej porze'),
  alwaysOpen('Całodobowe');

  const CoverageScenario(this.label);
  final String label;
}

/// Reach radius in meters, picked with a slider.
const coverageRadius = (min: 100.0, max: 1000.0, step: 50.0);

enum CoverageKind {
  /// An eligible AED within the threshold.
  covered,

  /// None (AEDs without information are never eligible).
  gap,
}

class CoverageCell {
  const CoverageCell({required this.kind, required this.nearestDistanceM, required this.nearestAedId});

  final CoverageKind kind;
  final int? nearestDistanceM;
  final String? nearestAedId;
}

typedef Site = ({String id, double lng, double lat});

class CoverageLayer {
  const CoverageLayer({required this.scenario, required this.thresholdM, required this.eligible, required this.data});

  final CoverageScenario scenario;
  final double thresholdM;

  /// The AEDs behind the white circles, so a tap can name the nearest one.
  final List<Site> eligible;

  /// GeoJSON FeatureCollection of MultiPolygons with a `kind` property.
  final Map<String, Object> data;
}
