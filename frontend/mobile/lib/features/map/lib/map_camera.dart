import 'dart:math';
import 'dart:ui';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import 'package:defiwawa/shared/geo/geo.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';

// Navigation view, as in Google Maps: street level, tilted, turned to the walking direction.
const _navZoom = 19.5;
const _navPitch = 50.0;
const _navEaseMs = 1000;
const _easeMs = 500;

Point toPoint(LngLat p) => Point(coordinates: Position(p.lng, p.lat));

/// The app has one map. Panels move the camera through this controller (only on explicit user actions,
/// DESIGN.md §12) instead of holding the map instance.
class MapCamera {
  MapboxMap? _map;

  /// Height covered by the bottom sheet or the find bar, so targets stay in the visible part of the map.
  double bottomInset = 0;

  /// Status bar height; the header sits below it.
  double topInset = 0;

  /// Map size in logical pixels.
  Size size = Size.zero;

  void attach(MapboxMap? map) => _map = map;

  // Right side keeps targets clear of the floating map controls.
  MbxEdgeInsets get _padding => MbxEdgeInsets(top: topInset + 96, left: 32, bottom: bottomInset + 32, right: 80);

  Future<void> focus(LngLat point) async {
    final map = _map;
    if (map == null) return;
    final zoom = (await map.getCameraState()).zoom;
    await map.easeTo(
      CameraOptions(center: toPoint(point), zoom: max(zoom, 16), bearing: 0, pitch: 0, padding: _padding),
      MapAnimationOptions(duration: _easeMs),
    );
  }

  /// Navigation: centers [point] heading-up ([bearing], degrees from north; null keeps the current one) and tilted.
  /// The point sits in the lower part of the visible map, so more of the way ahead shows.
  Future<void> navigate(LngLat point, double? bearing) async {
    final map = _map;
    if (map == null) return;
    // The map is flat everywhere else (DESIGN.md §12); tilt is allowed only while navigating.
    await map.setBounds(CameraBoundsOptions(maxPitch: _navPitch));
    final visible = size.height - bottomInset;
    await map.easeTo(
      CameraOptions(
        center: toPoint(point),
        zoom: _navZoom,
        bearing: bearing ?? (await map.getCameraState()).bearing,
        pitch: _navPitch,
        padding: MbxEdgeInsets(top: (visible / 2).roundToDouble(), left: 0, bottom: bottomInset, right: 0),
      ),
      MapAnimationOptions(duration: _navEaseMs),
    );
  }

  /// Back to the flat, north-up map after navigation.
  Future<void> exitNavigation() async {
    final map = _map;
    if (map == null) return;
    await map.easeTo(CameraOptions(bearing: 0, pitch: 0, padding: _padding), MapAnimationOptions(duration: _easeMs));
    await Future<void>.delayed(const Duration(milliseconds: _easeMs + 50));
    await map.setBounds(CameraBoundsOptions(maxPitch: 0));
  }

  Future<void> fitRoute(WalkingRoute route) async {
    final map = _map;
    if (map == null || route.coordinates.isEmpty) return;
    final lngs = route.coordinates.map((c) => c[0]), lats = route.coordinates.map((c) => c[1]);
    final camera = await map.cameraForCoordinateBounds(
      CoordinateBounds(
        southwest: toPoint(LngLat(lngs.reduce(min), lats.reduce(min))),
        northeast: toPoint(LngLat(lngs.reduce(max), lats.reduce(max))),
        infiniteBounds: false,
      ),
      _padding,
      0,
      0,
      17,
      null,
    );
    await map.easeTo(camera, MapAnimationOptions(duration: _easeMs));
  }

  Future<void> easeTo(LngLat center, double zoom) async =>
      _map?.easeTo(CameraOptions(center: toPoint(center), zoom: zoom), MapAnimationOptions(duration: _easeMs));
}

final mapCamera = MapCamera();
