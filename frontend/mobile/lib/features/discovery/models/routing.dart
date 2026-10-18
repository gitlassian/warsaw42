import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';

/// An address suggestion inside Warsaw; [location] is where the walk starts.
class AddressHit {
  const AddressHit({required this.id, required this.name, required this.detail, required this.location});

  final String id;
  final String name;
  final String? detail;
  final LngLat location;

  @override
  bool operator ==(Object other) =>
      other is AddressHit &&
      other.id == id &&
      other.name == name &&
      other.detail == detail &&
      other.location == location;

  @override
  int get hashCode => Object.hash(id, name, detail, location);
}

enum OriginSource { gps, manual }

/// Search start: GPS position or a point the user picked on the map (never a silent demo location).
class Origin extends LngLat {
  const Origin(super.lng, super.lat, {required this.source, this.accuracyM});

  final OriginSource source;
  final double? accuracyM;

  // Identity, like the web store: a new fix is a new origin even at the same spot.
  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}

enum LocationIssue {
  /// Permission refused.
  denied,

  /// Positioning failed or is switched off.
  unavailable,

  /// GPS position outside Warsaw.
  outside,

  /// Picked point outside Warsaw.
  outsidePick,
}

/// Map/list state of one walking time (POST /routes/etas element, ENDPOINTS.md §3): a pending request or a result.
sealed class EtaEntry {
  const EtaEntry();
}

final class EtaLoading extends EtaEntry {
  const EtaLoading();
}

final class EtaOk extends EtaEntry {
  const EtaOk({required this.durationSeconds, required this.distanceM});

  final double durationSeconds;
  final double distanceM;
}

/// no_route, not_found or provider_error; failed entries carry no numbers.
final class EtaFailed extends EtaEntry {
  const EtaFailed();
}

/// One turn-by-turn instruction (Mapbox, Polish). Distance and duration cover the walk to the next maneuver.
class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.street,
    required this.location,
    required this.distanceM,
    required this.durationSeconds,
  });

  final String instruction;

  /// Mapbox maneuver type ("depart", "turn", "arrive", …) and modifier ("left", "slight right", …).
  final String maneuverType;
  final String? maneuverModifier;
  final String? street;
  final LngLat location;
  final double distanceM;
  final double durationSeconds;
}

class WalkingRoute {
  const WalkingRoute({
    required this.aedId,
    required this.durationSeconds,
    required this.distanceM,
    required this.coordinates,
    required this.steps,
  });

  final String aedId;
  final double durationSeconds;
  final double distanceM;

  /// GeoJSON LineString coordinates, [lng, lat].
  final List<List<double>> coordinates;

  /// Walking order, from "depart" to "arrive"; empty when the provider sent none.
  final List<RouteStep> steps;

  Map<String, Object> get geometry => {'type': 'LineString', 'coordinates': coordinates};
}

class FindCandidate {
  const FindCandidate({required this.aed, required this.durationSeconds, required this.distanceM});

  final Aed aed;
  final double durationSeconds;
  final double distanceM;
}

enum FindStatus { found, noEligibleAed, routingUnavailable }

/// POST /aeds/find (ENDPOINTS.md §2). Ranking applies to evaluated candidates only.
class FindResult {
  const FindResult({
    required this.status,
    required this.selected,
    required this.route,
    required this.alternatives,
    required this.unknownAccessAlternatives,
    required this.evaluatedCount,
    required this.searchedRadiusM,
  });

  final FindStatus status;
  final FindCandidate? selected;
  final WalkingRoute? route;
  final List<FindCandidate> alternatives;

  /// Unknown hours or restricted access; never treated as eligible and carry no walking time.
  final List<Aed> unknownAccessAlternatives;
  final int evaluatedCount;
  final double searchedRadiusM;
}
