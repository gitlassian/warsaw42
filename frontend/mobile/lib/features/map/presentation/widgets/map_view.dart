import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/features/aeds/lib/aed_status.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/coverage/lib/coverage_geometry.dart';
import 'package:defiwawa/features/coverage/models/coverage.dart';
import 'package:defiwawa/features/coverage/providers/coverage_provider.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';
import 'package:defiwawa/features/discovery/providers/discovery_provider.dart';
import 'package:defiwawa/features/navigation/lib/progress.dart';
import 'package:defiwawa/features/navigation/providers/navigation_provider.dart';
import 'package:defiwawa/features/placement/providers/placement_provider.dart';
import 'package:defiwawa/features/map/lib/map_camera.dart';
import 'package:defiwawa/features/map/lib/map_layers.dart';

const _accuracyVisible = Duration(milliseconds: 2500);
const _pulse = Duration(seconds: 2);

/// Mapbox Standard (light, flat, north-up) locked to Warsaw, with AED markers, route, start point and coverage.
class MapView extends HookConsumerWidget {
  const MapView({
    super.key,
    required this.selectedId,
    required this.navigating,
    required this.showCoverage,
    required this.showPlacement,
    required this.bottomInset,
    required this.onLoadError,
    required this.onSelectAed,
  });

  final String? selectedId;
  final bool navigating;
  final bool showCoverage;

  /// "Gdzie dodać AED": the suggested sites and their reach.
  final bool showPlacement;

  /// Height covered by the sheet or the find bar; the Mapbox logo stays above it.
  final double bottomInset;
  final VoidCallback onLoadError;
  final ValueChanged<String> onSelectAed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = useRef<MapboxMap?>(null);
    // A cached style can finish loading before onMapCreated runs (seen on a cold simulator).
    final styleBeforeMap = useRef(false);
    // Set once the style and our layers are ready.
    final map = useState<MapboxMap?>(null);
    final images = useMemoized(() => <String>{});
    final dataVersion = useRef(0);
    final visibleKey = useState('');
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    mapCamera.topInset = MediaQuery.paddingOf(context).top;

    final aeds = ref.watch(aedsProvider.select((s) => s.aeds));
    final now = ref.watch(aedsProvider.select((s) => s.now));
    final selectedAed = ref.watch(aedsProvider.select((s) => selectedId == null ? null : s.byId[selectedId]));
    final filters = ref.watch(mapFiltersProvider);
    final origin = ref.watch(discoveryProvider.select((s) => s.origin));
    final etas = ref.watch(discoveryProvider.select((s) => s.etas));
    final route = ref.watch(discoveryProvider.select((s) => s.route));
    final coverageLayer = ref.watch(coverageProvider.select((s) => s.layer));
    final placement = ref.watch(placementViewProvider);
    final placementRadius = ref.watch(placementProvider.select((s) => s.data?.radiusM));
    final placementSelected = ref.watch(placementProvider.select((s) => s.selected));
    final livePosition = ref.watch(navigationProvider.select((s) => s.position));
    final following = ref.watch(navigationProvider.select((s) => s.following));
    final navigatedId = ref.watch(navigationProvider.select((s) => s.aedId));

    Future<void> ensureImages(StyleManager style, Iterable<String> ids) async {
      for (final id in ids) {
        if (images.add(id)) await style.addStyleImage(id, dpr, await MarkerImages.draw(id, dpr), false, [], [], null);
      }
    }

    // AED markers. Filters follow the clock: an AED that closes at 16:00 leaves the map without a reload.
    useEffect(() {
      final m = map.value;
      if (m == null) return null;
      final version = ++dataVersion.value;
      Map<String, Object> feature(Aed aed, {bool selected = false}) {
        final status = aedStatus(aed, now);
        return pointFeature(
          {
            'id': aed.id,
            'available': status.available ? 1 : 0,
            'sel': aed.id == selectedId ? 1 : 0,
            'pin': MarkerImages.pin(status, selected: selected),
            'pill': ?MarkerImages.pill(origin == null ? null : etas[aed.id]),
          },
          aed.location.lng,
          aed.location.lat,
        );
      }

      final features = [
        for (final aed in aeds)
          if (passesFilters(aed, now, filters)) feature(aed),
      ];
      final selected = [if (selectedAed != null) feature(selectedAed, selected: true)];
      () async {
        final props = [...features, ...selected].map((f) => f['properties'] as Map<String, Object?>);
        await ensureImages(m.style, {
          for (final p in props) ...[p['pin'] as String, ?p['pill'] as String?],
        });
        if (version != dataVersion.value) return;
        await setSourceData(m.style, MapSource.aeds, featureCollection(features));
        await setSourceData(m.style, MapSource.selected, featureCollection(selected));
      }();
      return null;
    }, [map.value, aeds, now, filters, etas, origin, selectedAed]);

    void setData(String source, Object data) {
      final style = map.value?.style;
      if (style != null) setSourceData(style, source, data);
    }

    useEffect(() {
      setData(MapSource.route, route?.geometry ?? emptyCollection);
      return null;
    }, [map.value, route]);

    useEffect(() {
      setData(MapSource.coverage, showCoverage && coverageLayer != null ? coverageLayer.data : emptyCollection);
      return null;
    }, [map.value, showCoverage, coverageLayer]);

    // Suggested AED sites: a numbered disc and a dashed reach circle around each one.
    useEffect(() {
      final picks = showPlacement && placementRadius != null ? placement?.picks ?? const [] : const [];
      setData(
        MapSource.placementReach,
        featureCollection([
          for (final p in picks)
            {
              'type': 'Feature',
              'properties': const <String, Object>{},
              'geometry': circlePolygon(LngLat(p.lng, p.lat), placementRadius!),
            },
        ]),
      );
      setData(
        MapSource.placementSites,
        featureCollection([
          for (final p in picks)
            pointFeature({'rank': p.rank, 'sel': p.rank == placementSelected ? 1 : 0}, p.lng, p.lat),
        ]),
      );
      return null;
    }, [map.value, showPlacement, placement, placementRadius, placementSelected]);

    // Accuracy area (DESIGN.md §12): shown for a moment after a GPS fix, then faded out, as in Google Maps.
    // Hidden while navigating, where the walker is an arrow on the route.
    useEffect(() {
      final style = map.value?.style;
      if (style == null) return null;
      final accuracyM = origin?.source == OriginSource.gps && livePosition == null ? origin?.accuracyM : null;
      setSourceData(style, MapSource.accuracy, accuracyM == null ? emptyCollection : circlePolygon(origin!, accuracyM));
      if (accuracyM == null) return null;
      style.setStyleLayerProperty(MapLayer.accuracy, 'fill-opacity', accuracyOpacity);
      final timer = Timer(_accuracyVisible, () => style.setStyleLayerProperty(MapLayer.accuracy, 'fill-opacity', 0));
      return timer.cancel;
    }, [map.value, origin, livePosition]);

    // Walking direction along the navigated route at the live position: turns the map and the arrow.
    final heading = useMemoized(() {
      if (livePosition == null || route == null || route.aedId != navigatedId) return null;
      final plan = routePlan(route);
      return plan.coordinates.length > 1 ? headingAt(plan, locateOnRoute(plan, livePosition).alongM) : null;
    }, [livePosition, route, navigatedId]);

    // The start point; while navigating, the live position replaces it.
    final me = switch ((livePosition, origin)) {
      (final live?, _) =>
        heading == null
            ? pointFeature({'kind': 'dot'}, live.lng, live.lat)
            : pointFeature({'kind': 'arrow', 'rotation': heading}, live.lng, live.lat),
      (null, final start?) => pointFeature(
        {'kind': start.source == OriginSource.gps ? 'dot' : 'pick'},
        start.lng,
        start.lat,
      ),
      _ => null,
    };
    useEffect(() {
      setData(MapSource.me, featureCollection([?me]));
      return null;
    }, [map.value, origin, livePosition, heading]);

    // Soft halo pulsing out of the GPS dot: a live position without a constant area on the map.
    final hasDot = me != null && (me['properties'] as Map)['kind'] == 'dot';
    useEffect(() {
      final style = map.value?.style;
      if (style == null || !hasDot) return null;
      Future<void> set(Map<String, Object> paint) async {
        for (final MapEntry(:key, :value) in paint.entries) {
          await style.setStyleLayerProperty(MapLayer.halo, key, value);
        }
      }

      Future<void> pulse() async {
        await set({
          'circle-radius-transition': {'duration': 0, 'delay': 0},
          'circle-opacity-transition': {'duration': 0, 'delay': 0},
          'circle-radius': 10,
          'circle-opacity': 0.4,
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await set({
          'circle-radius-transition': {'duration': 1900, 'delay': 0},
          'circle-opacity-transition': {'duration': 1900, 'delay': 0},
          'circle-radius': 30,
          'circle-opacity': 0,
        });
      }

      if (reduceMotion) {
        set({'circle-radius': 16, 'circle-opacity': 0.2});
        return null;
      }
      pulse();
      final timer = Timer.periodic(_pulse, (_) => pulse());
      return timer.cancel;
    }, [map.value, hasDot, reduceMotion]);

    // Move the camera only after an explicit selection or a new route (DESIGN.md §12).
    // Navigation moves the camera itself (heading-up); leaving it shows the whole route again.
    useEffect(() {
      if (map.value == null || selectedAed == null || navigating) return null;
      Future.microtask(
        () => route?.aedId == selectedAed.id ? mapCamera.fitRoute(route!) : mapCamera.focus(selectedAed.location),
      );
      return null;
    }, [map.value, selectedAed, route, navigating]);

    useEffect(() {
      if (map.value != null && following && livePosition != null) mapCamera.navigate(livePosition, heading);
      return null;
    }, [map.value, following, livePosition, heading]);

    // Walking-time pills for individually visible markers, debounced and batched in the store.
    useEffect(() {
      if (origin == null || visibleKey.value.isEmpty) return null;
      final timer = Timer(
        const Duration(milliseconds: 300),
        () => ref.read(discoveryProvider.notifier).requestEtas(visibleKey.value.split(',')),
      );
      return timer.cancel;
    }, [origin, visibleKey.value]);

    // Keep the Mapbox logo above the bottom sheet; no attribution button, like the web map.
    useEffect(() {
      final m = map.value;
      if (m == null) return null;
      m.logo.updateSettings(LogoSettings(marginLeft: 10, marginBottom: bottomInset + 10));
      m.attribution.updateSettings(AttributionSettings(enabled: false));
      return null;
    }, [map.value, bottomInset]);

    Future<void> onStyleLoaded(MapboxMap m) async {
      final style = m.style;
      await style.setStyleImportConfigProperty('basemap', 'lightPreset', 'day');
      await style.setStyleImportConfigProperty('basemap', 'show3dObjects', false);
      images.clear();
      await addAppLayers(style, dpr);
      mapCamera.attach(m);
      map.value = m;
    }

    Future<void> onMapCreated(MapboxMap m) async {
      instance.value = m;
      await m.gestures.updateSettings(
        GesturesSettings(rotateEnabled: false, pitchEnabled: false, simultaneousRotateAndPinchToZoomEnabled: false),
      );
      await m.compass.updateSettings(CompassSettings(enabled: false));
      await m.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
      // Flat map, no rotation or tilt, locked to Warsaw.
      await m.setBounds(
        CameraBoundsOptions(
          bounds: CoordinateBounds(
            southwest: toPoint(warsawSouthWest),
            northeast: toPoint(warsawNorthEast),
            infiniteBounds: false,
          ),
          minZoom: 10,
          maxPitch: 0,
        ),
      );
      if (styleBeforeMap.value) onStyleLoaded(m);
    }

    Future<List<Map<String?, Object?>>> query(
      MapboxMap m,
      ScreenCoordinate at,
      double radius,
      List<String> layers,
    ) async {
      final hits = await m.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenBox(
          ScreenBox(
            min: ScreenCoordinate(x: at.x - radius, y: at.y - radius),
            max: ScreenCoordinate(x: at.x + radius, y: at.y + radius),
          ),
        ),
        RenderedQueryOptions(layerIds: layers),
      );
      return [for (final hit in hits) ?hit?.queriedFeature.feature];
    }

    Future<void> onTap(MapContentGestureContext context) async {
      final m = map.value;
      if (m == null) return;
      final point = LngLat(context.point.coordinates.lng.toDouble(), context.point.coordinates.lat.toDouble());
      if (ref.read(discoveryProvider).picking) return ref.read(discoveryProvider.notifier).pickOrigin(point);

      // Suggested sites sit above the AED markers; their source is empty unless the panel is open.
      final sites = await query(m, context.touchPosition, 8, [MapLayer.placementSite]);
      final rank = sites.isEmpty ? null : (sites.first['properties'] as Map?)?['rank'];
      if (rank is num) return ref.read(placementProvider.notifier).select(rank.toInt());

      // Markers keep a 48 hit area (DESIGN.md §4): their images already pad the pin, plus 8 around the tap.
      final aedHits = await query(m, context.touchPosition, 8, MapLayer.aedTargets);
      final aedId = aedHits.isEmpty ? null : (aedHits.first['properties'] as Map?)?['id'];
      if (aedId != null) return onSelectAed(aedId.toString());

      final clusters = await query(m, context.touchPosition, 4, [MapLayer.cluster]);
      if (clusters.isNotEmpty) {
        final cluster = clusters.first;
        final expansion = await m.getGeoJsonClusterExpansionZoom(MapSource.aeds, cluster);
        final zoom = double.tryParse(expansion.value ?? '');
        final [lng, lat] = ((cluster['geometry'] as Map)['coordinates'] as List).cast<num>();
        if (zoom != null) mapCamera.easeTo(LngLat(lng.toDouble(), lat.toDouble()), zoom);
        return;
      }

      final coverage = ref.read(coverageProvider.notifier);
      final layer = ref.read(coverageProvider).layer;
      final areas = await query(m, context.touchPosition, 0, [MapLayer.coverageFill, MapLayer.coverageHalo]);
      if (areas.isEmpty || layer == null) return coverage.selectCell(null);
      final nearest = nearestSite(point.lng, point.lat, layer.eligible);
      coverage.selectCell(
        CoverageCell(
          kind: (areas.first['properties'] as Map?)?['kind'] == 'covered' ? CoverageKind.covered : CoverageKind.gap,
          nearestDistanceM: nearest?.distanceM.round(),
          nearestAedId: nearest?.site.id,
        ),
      );
    }

    // AEDs drawn on their own (not in a cluster) right now, for walking-time pills.
    Future<void> onIdle(MapIdleEventData _) async {
      final m = map.value;
      if (m == null) return;
      final size = mapCamera.size;
      final hits = await m.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenBox(
          ScreenBox(
            min: ScreenCoordinate(x: 0, y: 0),
            max: ScreenCoordinate(x: size.width, y: size.height),
          ),
        ),
        RenderedQueryOptions(layerIds: [MapLayer.aedPin]),
      );
      final ids = {for (final hit in hits) ((hit?.queriedFeature.feature['properties'] as Map?)?['id']).toString()}
        ..remove('null');
      final key = (ids.toList()..sort()).join(',');
      if (key != visibleKey.value) visibleKey.value = key;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        mapCamera.size = constraints.biggest;
        return Semantics(
          label: 'Mapa defibrylatorów w Warszawie',
          child: MapWidget(
            styleUri: MapboxStyles.STANDARD,
            cameraOptions: CameraOptions(center: toPoint(warsawCenter), zoom: 11),
            onMapCreated: onMapCreated,
            onStyleLoadedListener: (_) {
              if (instance.value case final m?) {
                onStyleLoaded(m);
              } else {
                styleBeforeMap.value = true;
              }
            },
            onMapLoadErrorListener: (_) {
              if (map.value == null) onLoadError();
            },
            onTapListener: onTap,
            onScrollListener: (_) => ref.read(navigationProvider.notifier).stopFollowing(),
            onMapIdleListener: onIdle,
          ),
        );
      },
    );
  }
}
