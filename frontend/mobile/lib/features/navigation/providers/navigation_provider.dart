import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:defiwawa/features/discovery/models/routing.dart';
import 'package:defiwawa/features/discovery/providers/discovery_provider.dart';
import 'package:defiwawa/features/discovery/services/discovery_services.dart';
import 'package:defiwawa/features/map/lib/map_camera.dart';
import 'package:defiwawa/features/navigation/lib/progress.dart';

/// off: no live position (manual start point); waiting: before the first fix; denied/unavailable: GPS problems.
enum Tracking { off, waiting, on, denied, unavailable }

const _keep = Object();

class NavigationState {
  const NavigationState({
    this.aedId,
    this.tracking = Tracking.off,
    this.position,
    this.previewIndex,
    this.following = false,
  });

  final String? aedId;
  final Tracking tracking;

  /// Live GPS position; the search origin stays where the route started.
  final Origin? position;

  /// Step the user is browsing in the banner; null follows the live position.
  final int? previewIndex;

  /// The camera follows the walker until the user pans the map.
  final bool following;

  NavigationState copyWith({
    Object? aedId = _keep,
    Tracking? tracking,
    Object? position = _keep,
    Object? previewIndex = _keep,
    bool? following,
  }) => NavigationState(
    aedId: aedId == _keep ? this.aedId : aedId as String?,
    tracking: tracking ?? this.tracking,
    position: position == _keep ? this.position : position as Origin?,
    previewIndex: previewIndex == _keep ? this.previewIndex : previewIndex as int?,
    following: following ?? this.following,
  );
}

final _plans = Expando<RoutePlan>();

/// Route line measured once per route.
RoutePlan routePlan(WalkingRoute route) => _plans[route] ??= planRoute(route.coordinates, route.steps);

class NavigationNotifier extends Notifier<NavigationState> {
  void Function()? _stopWatch;

  @override
  NavigationState build() {
    ref.onDispose(() => _stopWatch?.call());
    return const NavigationState();
  }

  DiscoveryNotifier get _discovery => ref.read(discoveryProvider.notifier);

  /// Turn-by-turn mode: follows GPS when the route starts at the user's position, otherwise previews the steps.
  void startNavigation(String aedId) {
    stopNavigation();
    state = NavigationState(aedId: aedId, previewIndex: 0);
    final discovery = ref.read(discoveryProvider);
    if (discovery.origin?.source == OriginSource.gps) return startTracking();
    final route = discovery.route;
    if (route?.aedId == aedId) previewStep(route!, 0);
  }

  void startTracking() {
    _stopWatch?.call();
    state = state.copyWith(tracking: Tracking.waiting, previewIndex: null, following: true);
    _stopWatch = ref.read(geolocationServiceProvider).watchPosition((position) {
      final origin = position.origin;
      if (origin != null) {
        state = state.copyWith(tracking: Tracking.on, position: origin);
      } else if (position.issue == LocationIssue.denied) {
        _stopWatch?.call();
        _stopWatch = null;
        state = state.copyWith(tracking: Tracking.denied, previewIndex: 0, following: false);
      } else {
        // Fixes often come back (tunnels, buildings): keep watching.
        state = state.copyWith(tracking: Tracking.unavailable);
      }
    });
  }

  void stopNavigation() {
    _stopWatch?.call();
    _stopWatch = null;
    state = const NavigationState();
  }

  /// Shows a step in the banner and turns the map to look along it from its maneuver.
  void previewStep(WalkingRoute route, int index) {
    if (index < 0 || index >= route.steps.length) return;
    state = state.copyWith(previewIndex: index, following: false);
    final plan = routePlan(route);
    mapCamera.navigate(
      route.steps[index].location,
      plan.coordinates.length > 1 ? headingAt(plan, plan.stepAlongM[index]) : 0,
    );
  }

  /// A route from a picked point: start again from the user's real position.
  Future<void> navigateFromHere(String aedId) async {
    if (await _discovery.locate() == null) return;
    await _discovery.routeTo(aedId);
    startTracking();
  }

  /// The map's location button while navigating: back to the live position, or start from it.
  void showMyPosition() {
    // Not `locate()` alone: a new search origin would clear the route being walked.
    if (state.tracking case Tracking.on || Tracking.waiting || Tracking.unavailable) {
      followPosition();
    } else if (state.aedId case final aedId?) {
      navigateFromHere(aedId);
    }
  }

  /// Back to the live position after browsing steps or panning the map.
  void followPosition() => state = state.copyWith(previewIndex: null, following: true);

  void stopFollowing() {
    if (state.following) state = state.copyWith(following: false);
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, NavigationState>(NavigationNotifier.new);

class NavigationView {
  const NavigationView({
    required this.route,
    required this.index,
    required this.distanceM,
    required this.remainingM,
    required this.remainingSeconds,
    required this.live,
    required this.offRoute,
    required this.arrived,
  });

  final WalkingRoute route;
  List<RouteStep> get steps => route.steps;

  /// Step shown in the banner.
  final int index;

  /// Meters to the shown step's maneuver; null for the start step.
  final double? distanceM;
  final double remainingM;
  final double remainingSeconds;

  /// The banner follows the live position (not browsing steps).
  final bool live;
  final bool offRoute;
  final bool arrived;
}

/// Banner and panel state for the route being navigated, or null when there is none.
final navigationViewProvider = Provider<NavigationView?>((ref) {
  final route = ref.watch(discoveryProvider.select((s) => s.route));
  final nav = ref.watch(navigationProvider);
  if (route == null || route.aedId != nav.aedId) return null;
  final steps = route.steps;
  final position = nav.position;
  final plan = routePlan(route);
  final progress = position != null && plan.coordinates.length > 1 ? locateOnRoute(plan, position) : null;
  final offRoute = progress != null && isOffRoute(progress, position?.accuracyM ?? 0);
  final onRoute = progress != null && !offRoute ? progress : null;
  final live = nav.previewIndex == null && onRoute != null;
  final index = onRoute != null && live
      ? upcomingStep(plan, onRoute.alongM)
      : min(nav.previewIndex ?? 0, max(0, steps.length - 1));
  // Provider totals are the reference; the measured line only gives the share still to walk.
  final share = onRoute != null && plan.totalM > 0 ? max(0.0, 1 - onRoute.alongM / plan.totalM) : 1.0;
  final maneuverAlongM = index < plan.stepAlongM.length ? plan.stepAlongM[index] : null;
  // Without steps (older backend) the banner counts down to the AED itself.
  final distanceM = steps.isEmpty
      ? route.distanceM * share
      : onRoute != null && live && maneuverAlongM != null
      ? max(0.0, maneuverAlongM - onRoute.alongM)
      : index > 0
      ? steps[index - 1].distanceM
      : null;
  return NavigationView(
    route: route,
    index: index,
    distanceM: distanceM,
    remainingM: route.distanceM * share,
    remainingSeconds: route.durationSeconds * share,
    live: live,
    offRoute: offRoute,
    // Browsing steps shows them even at the destination.
    arrived: live && hasArrived(plan, onRoute),
  );
});
