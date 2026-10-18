import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';

/// Mapbox misses Warsaw house numbers that nearby towns share ("Marszałkowska 10") unless the query names the
/// city, but finds half-typed streets only without it. So the city is added once a house number is typed.
String geocodingQuery(String query) =>
    RegExp(r'\d').hasMatch(query) && !RegExp('warszaw', caseSensitive: false).hasMatch(query)
    ? '$query, Warszawa'
    : query;

/// Suggestions inside the city only (the bounding box also reaches nearby towns) from a Mapbox Geocoding v6
/// forward response. The walking route starts at the address's routable point, the entrance on the street.
List<AddressHit> parseAddressHits(Map<String, dynamic> json, bool Function(LngLat) isInside) {
  final features = (json['features'] as List?) ?? const [];
  return [
    for (final (i, feature) in features.cast<Map<String, dynamic>>().indexed)
      if (_hit(feature, i) case final hit when isInside(hit.location)) hit,
  ];
}

AddressHit _hit(Map<String, dynamic> feature, int index) {
  final properties = feature['properties'] as Map<String, dynamic>;
  final coordinates = properties['coordinates'] as Map<String, dynamic>;
  final routable = coordinates['routable_points'] as List?;
  final point = (routable?.isNotEmpty ?? false) ? routable!.first as Map<String, dynamic> : coordinates;
  // "00-590 Warszawa, województwo mazowieckie, Polska" -> "00-590 Warszawa"
  final place = properties['place_formatted'] as String?;
  return AddressHit(
    id: feature['id'] as String? ?? '$index',
    name: properties['name'] as String,
    detail: place?.split(',').first.trim(),
    location: LngLat((point['longitude'] as num).toDouble(), (point['latitude'] as num).toDouble()),
  );
}
