import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/shared/lib/env.dart';
import 'package:defiwawa/shared/lib/supabase_client.dart';
import 'package:defiwawa/features/aeds/services/aed_service.dart';
import 'package:defiwawa/features/discovery/lib/geocoding.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';

/// Mapbox Geocoding v6 with the public map token (the same token the map uses), limited to Warsaw.
class GeocodingService {
  Future<List<AddressHit>> searchAddresses(String query) async {
    final uri = Uri.https('api.mapbox.com', '/search/geocode/v6/forward', {
      'q': geocodingQuery(query),
      'access_token': Env.mapboxToken,
      'country': 'pl',
      'language': 'pl',
      'autocomplete': 'true',
      // Nearby towns share street names: ask for more, keep five inside the city.
      'limit': '10',
      'types': 'address,street',
      'bbox': [warsawSouthWest.lng, warsawSouthWest.lat, warsawNorthEast.lng, warsawNorthEast.lat].join(','),
      'proximity': '${warsawCenter.lng},${warsawCenter.lat}',
    });
    final response = await http.get(uri);
    if (response.statusCode >= 300) throw Exception('geocoding ${response.statusCode}');
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return parseAddressHits(json, isInsideWarsaw).take(5).toList();
  }
}

/// A GPS fix, or why there is none: permission refused ([LocationIssue.denied]) or positioning failed or off.
typedef PositionResult = ({Origin? origin, LocationIssue? issue});

PositionResult _fix(Position p) =>
    (origin: Origin(p.longitude, p.latitude, source: OriginSource.gps, accuracyM: p.accuracy), issue: null);
PositionResult _failed(LocationIssue issue) => (origin: null, issue: issue);

class GeolocationService {
  /// Location services on and permission granted, asking for it when needed.
  Future<LocationIssue?> _ready() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationIssue.unavailable;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    return switch (permission) {
      LocationPermission.denied || LocationPermission.deniedForever => LocationIssue.denied,
      LocationPermission.unableToDetermine => LocationIssue.unavailable,
      _ => null,
    };
  }

  /// One-shot GPS fix. Resolves with the position or the reason it is unavailable.
  /// A precise fix often times out indoors, so a failed one falls back to a coarse (Wi-Fi or cached)
  /// position, which is still good enough to find nearby AEDs.
  Future<PositionResult> getCurrentPosition() async {
    final issue = await _ready();
    if (issue != null) return _failed(issue);
    try {
      return _fix(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
        ),
      );
    } catch (_) {}
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null && DateTime.now().difference(cached.timestamp) < const Duration(minutes: 5)) {
        return _fix(cached);
      }
      return _fix(
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
        ),
      );
    } on PermissionDeniedException {
      return _failed(LocationIssue.denied);
    } catch (_) {
      return _failed(LocationIssue.unavailable);
    }
  }

  /// Continuous GPS fixes while navigating. Returns a function that stops watching.
  void Function() watchPosition(void Function(PositionResult position) onUpdate) {
    StreamSubscription<Position>? subscription;
    var stopped = false;
    _ready().then((issue) {
      if (stopped) return;
      if (issue != null) return onUpdate(_failed(issue));
      subscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
          ).listen(
            (p) => onUpdate(_fix(p)),
            onError: (Object e) =>
                onUpdate(_failed(e is PermissionDeniedException ? LocationIssue.denied : LocationIssue.unavailable)),
          );
    });
    return () {
      stopped = true;
      subscription?.cancel();
    };
  }
}

/// Edge Functions aeds-find, routes-etas and routes-walking (ENDPOINTS.md "Finding and routing").
/// Their AED view is slim; the full record comes from the cached AED list by id.
class RoutingService {
  RoutingService(this._client, this._aeds);

  final SupabaseClient _client;
  final AedService _aeds;

  static Map<String, double> _point(LngLat p) => {'latitude': p.lat, 'longitude': p.lng};

  static double _num(Object? n) => (n as num).toDouble();

  static WalkingRoute _route(String aedId, Map<String, dynamic> r) => WalkingRoute(
    aedId: aedId,
    durationSeconds: _num(r['duration_seconds']),
    distanceM: _num(r['distance_m']),
    coordinates: [
      for (final c in (r['geometry'] as Map)['coordinates'] as List) [_num((c as List)[0]), _num(c[1])],
    ],
    steps: [
      for (final st in ((r['steps'] as List?) ?? const []).cast<Map<String, dynamic>>())
        RouteStep(
          instruction: st['instruction'] as String,
          maneuverType: st['maneuver_type'] as String,
          maneuverModifier: st['maneuver_modifier'] as String?,
          street: st['street'] as String?,
          location: LngLat(_num((st['location'] as List)[0]), _num((st['location'] as List)[1])),
          distanceM: _num(st['distance_m']),
          durationSeconds: _num(st['duration_seconds']),
        ),
    ],
  );

  Future<FindResult> findAed(LngLat origin) async {
    final (response, aeds) = await (
      _client.callFunction('aeds-find', {'origin': _point(origin)}),
      _aeds.fetchAeds(),
    ).wait;
    final data = response['data'] as Map<String, dynamic>;
    final search = (response['meta'] as Map)['search'] as Map;
    final byId = {for (final aed in aeds) aed.id: aed};
    String idOf(Object? ref) => ((ref as Map)['aed'] as Map)['id'].toString();

    // Without walking times (routing_unavailable) an AED is not a ranked result.
    FindCandidate? candidate(Map<String, dynamic> c) {
      final aed = byId[idOf(c)];
      final walking = c['walking'] as Map?;
      if (aed == null || walking == null) return null;
      return FindCandidate(
        aed: aed,
        durationSeconds: _num(walking['duration_seconds']),
        distanceM: _num(walking['distance_m']),
      );
    }

    final rawSelected = data['selected'] as Map<String, dynamic>?;
    final selected = rawSelected == null ? null : candidate(rawSelected);
    final rawRoute = rawSelected?['route'] as Map<String, dynamic>?;
    return FindResult(
      status: switch (data['status']) {
        'found' => FindStatus.found,
        'no_eligible_aed' => FindStatus.noEligibleAed,
        _ => FindStatus.routingUnavailable,
      },
      selected: selected,
      route: selected != null && rawRoute != null ? _route(selected.aed.id, rawRoute) : null,
      alternatives: [for (final c in (data['alternatives'] as List).cast<Map<String, dynamic>>()) ?candidate(c)],
      unknownAccessAlternatives: [for (final u in data['unknown_access_alternatives'] as List) ?byId[idOf(u)]],
      evaluatedCount: (search['evaluated_count'] as num).toInt(),
      searchedRadiusM: _num(search['searched_radius_m']),
    );
  }

  Future<Map<String, EtaEntry>> fetchEtas(LngLat origin, List<String> aedIds) async {
    final response = await _client.callFunction('routes-etas', {'origin': _point(origin), 'aed_ids': aedIds});
    return {
      for (final e in (response['data'] as List).cast<Map<String, dynamic>>())
        e['aed_id'].toString(): e['status'] == 'ok' && e['duration_seconds'] != null && e['distance_m'] != null
            ? EtaOk(durationSeconds: _num(e['duration_seconds']), distanceM: _num(e['distance_m']))
            : const EtaFailed(),
    };
  }

  Future<WalkingRoute> fetchWalkingRoute(LngLat origin, String aedId) async {
    final response = await _client.callFunction('routes-walking', {'origin': _point(origin), 'aed_id': aedId});
    return _route(aedId, response['data'] as Map<String, dynamic>);
  }
}

final geocodingServiceProvider = Provider((ref) => GeocodingService());
final geolocationServiceProvider = Provider((ref) => GeolocationService());
final routingServiceProvider = Provider(
  (ref) => RoutingService(ref.watch(supabaseClientProvider), ref.watch(aedServiceProvider)),
);
