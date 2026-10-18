import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';
import 'package:defiwawa/features/discovery/services/discovery_services.dart';

/// Pills are computed only for nearby markers, in bounded batches (PLAN.md §3).
const _etaRadiusM = 2000;
const _etaBatchSize = 20;

sealed class SearchState {
  const SearchState();
}

final class SearchIdle extends SearchState {
  const SearchIdle();
}

final class SearchSearching extends SearchState {
  const SearchSearching();
}

final class SearchDone extends SearchState {
  const SearchDone(this.result);
  final FindResult result;
}

final class SearchFailed extends SearchState {
  const SearchFailed();
}

enum RoutingStatus { loading, failed }

const _keep = Object();

class DiscoveryState {
  const DiscoveryState({
    this.origin,
    this.locating = false,
    this.issue,
    this.picking = false,
    this.search = const SearchIdle(),
    this.etas = const {},
    this.route,
    this.routing,
  });

  final Origin? origin;
  final bool locating;
  final LocationIssue? issue;

  /// Waiting for the user to tap a start point on the map.
  final bool picking;
  final SearchState search;
  final Map<String, EtaEntry> etas;
  final WalkingRoute? route;
  final ({String aedId, RoutingStatus status})? routing;

  DiscoveryState copyWith({
    Object? origin = _keep,
    bool? locating,
    Object? issue = _keep,
    bool? picking,
    SearchState? search,
    Map<String, EtaEntry>? etas,
    Object? route = _keep,
    Object? routing = _keep,
  }) => DiscoveryState(
    origin: origin == _keep ? this.origin : origin as Origin?,
    locating: locating ?? this.locating,
    issue: issue == _keep ? this.issue : issue as LocationIssue?,
    picking: picking ?? this.picking,
    search: search ?? this.search,
    etas: etas ?? this.etas,
    route: route == _keep ? this.route : route as WalkingRoute?,
    routing: routing == _keep ? this.routing : routing as ({String aedId, RoutingStatus status})?,
  );
}

class DiscoveryNotifier extends Notifier<DiscoveryState> {
  // Bumped on every new search or cancel so stale responses are dropped.
  int _searchToken = 0;
  void Function(Origin origin)? _onPicked;

  @override
  DiscoveryState build() => const DiscoveryState();

  RoutingService get _routing => ref.read(routingServiceProvider);

  void _setOrigin(Origin origin) {
    state = state.copyWith(
      origin: origin,
      issue: null,
      etas: const {},
      route: null,
      routing: null,
      search: state.search is SearchSearching ? state.search : const SearchIdle(),
    );
  }

  /// GPS fix inside Warsaw, or null with `issue` set. A position outside the city is reported, never clamped.
  Future<Origin?> locate() async {
    state = state.copyWith(locating: true, issue: null);
    final position = await ref.read(geolocationServiceProvider).getCurrentPosition();
    state = state.copyWith(locating: false);
    final origin = position.origin;
    if (origin == null) {
      state = state.copyWith(issue: position.issue);
      return null;
    }
    if (!isInsideWarsaw(origin)) {
      state = state.copyWith(issue: LocationIssue.outside);
      return null;
    }
    _setOrigin(origin);
    return origin;
  }

  Future<FindResult?> _runFind(Origin origin, int token) async {
    // The server finds by the real clock, so the map leaves any time preview to match the result.
    ref.read(aedsProvider.notifier).resetViewTime();
    try {
      final result = await _routing.findAed(origin);
      if (token != _searchToken) return null;
      state = state.copyWith(
        search: SearchDone(result),
        route: result.route,
        routing: null,
        etas: {
          ...state.etas,
          for (final c in [?result.selected, ...result.alternatives])
            c.aed.id: EtaOk(durationSeconds: c.durationSeconds, distanceM: c.distanceM),
        },
      );
      return result;
    } catch (_) {
      if (token == _searchToken) state = state.copyWith(search: const SearchFailed());
      return null;
    }
  }

  /// "Znajdź defibrylator": a picked start point if there is one, otherwise a fresh GPS fix.
  Future<FindResult?> findNearest() async {
    final token = ++_searchToken;
    state = state.copyWith(search: const SearchSearching());
    final origin = state.origin;
    final start = origin?.source == OriginSource.manual ? origin : await locate();
    if (token != _searchToken) return null;
    if (start == null) {
      state = state.copyWith(search: const SearchIdle());
      return null;
    }
    return _runFind(start, token);
  }

  Future<FindResult?> findFrom(Origin origin) {
    final token = ++_searchToken;
    state = state.copyWith(search: const SearchSearching());
    return _runFind(origin, token);
  }

  /// Closing the selected AED also removes its walking route and a picked or typed start point from the map.
  void clearSelection() {
    // A GPS origin is the user's real position and stays.
    final manual = state.origin?.source == OriginSource.manual;
    state = state.copyWith(route: null, routing: null, origin: manual ? null : _keep, etas: manual ? const {} : null);
  }

  void cancelSearch() {
    _searchToken++;
    state = state.copyWith(search: const SearchIdle());
  }

  /// Starts manual origin selection; [then] runs once a valid point is picked.
  void startPicking([void Function(Origin origin)? then]) {
    _onPicked = then;
    state = state.copyWith(picking: true, issue: null);
  }

  void stopPicking() {
    _onPicked = null;
    state = state.copyWith(picking: false, issue: state.issue == LocationIssue.outsidePick ? null : _keep);
  }

  void pickOrigin(LngLat point) {
    if (!isInsideWarsaw(point)) {
      state = state.copyWith(issue: LocationIssue.outsidePick);
      return;
    }
    final origin = Origin(point.lng, point.lat, source: OriginSource.manual);
    final then = _onPicked;
    stopPicking();
    _setOrigin(origin);
    then?.call(origin);
  }

  /// Search from a typed address: the same manual start point as one picked on the map.
  Future<FindResult?> findFromAddress(LngLat location) async {
    // The suggestions are already inside Warsaw; checked again because they come from an outside service.
    if (!isInsideWarsaw(location)) {
      state = state.copyWith(issue: LocationIssue.outsidePick);
      return null;
    }
    final origin = Origin(location.lng, location.lat, source: OriginSource.manual);
    stopPicking();
    _setOrigin(origin);
    return findFrom(origin);
  }

  /// Requests walking times for the nearest of [aedIds] that have none yet.
  Future<void> requestEtas(Iterable<String> aedIds) async {
    final origin = state.origin;
    if (origin == null) return;
    final byId = ref.read(aedsProvider).byId;
    final nearby = [
      for (final id in aedIds)
        if (!state.etas.containsKey(id) && byId[id] != null)
          (id: id, distance: distanceMeters(origin, byId[id]!.location)),
    ].where((c) => c.distance <= _etaRadiusM).toList()..sort((a, b) => a.distance.compareTo(b.distance));
    final ids = nearby.take(_etaBatchSize).map((c) => c.id).toList();
    if (ids.isEmpty) return;

    void mark(EtaEntry Function(String id) entry) =>
        state = state.copyWith(etas: {...state.etas, for (final id in ids) id: entry(id)});
    mark((_) => const EtaLoading());
    try {
      final result = await _routing.fetchEtas(origin, ids);
      if (state.origin == origin) mark((id) => result[id] ?? const EtaFailed());
    } catch (_) {
      if (state.origin == origin) mark((_) => const EtaFailed());
    }
  }

  /// "Wyznacz trasę" for a manually selected AED.
  Future<void> routeTo(String aedId) async {
    state = state.copyWith(routing: (aedId: aedId, status: RoutingStatus.loading));
    final origin = state.origin ?? await locate();
    // A fresh GPS origin resets `routing`, so mark the request again.
    state = state.copyWith(routing: origin != null ? (aedId: aedId, status: RoutingStatus.loading) : null);
    if (origin == null) return;
    try {
      final route = await _routing.fetchWalkingRoute(origin, aedId);
      if (state.origin != origin) return;
      state = state.copyWith(
        route: route,
        routing: null,
        etas: {
          ...state.etas,
          aedId: EtaOk(durationSeconds: route.durationSeconds, distanceM: route.distanceM),
        },
      );
    } catch (_) {
      state = state.copyWith(routing: (aedId: aedId, status: RoutingStatus.failed));
    }
  }

  /// New route from the walker's live position, after navigation went off the route.
  Future<void> rerouteFrom(Origin origin, String aedId) async {
    if (!isInsideWarsaw(origin)) {
      state = state.copyWith(issue: LocationIssue.outside);
      return;
    }
    _setOrigin(origin);
    return routeTo(aedId);
  }
}

final discoveryProvider = NotifierProvider<DiscoveryNotifier, DiscoveryState>(DiscoveryNotifier.new);
