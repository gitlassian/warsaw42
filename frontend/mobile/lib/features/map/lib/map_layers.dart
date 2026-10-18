import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import 'package:defiwawa/shared/geo/warsaw_boundary.dart';
import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/aeds/lib/aed_status.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';

// Sources and layers on top of the Mapbox Standard style, as on web. AED markers, the start point and the
// walker are symbol layers with bitmaps drawn here from the app's fonts and icons, so they match the web's
// HTML markers and move with the map without lag.

abstract final class MapSource {
  static const aeds = 'aeds';
  static const selected = 'selected-aed';
  static const route = 'route';
  static const coverage = 'coverage';
  static const accuracy = 'origin-accuracy';
  static const boundary = 'warsaw-boundary';

  /// Suggested AED sites ("Gdzie dodać AED") and their reach.
  static const placementSites = 'placement-sites';
  static const placementReach = 'placement-reach';

  /// The search start point or the live position while navigating.
  static const me = 'me';
}

abstract final class MapLayer {
  static const coverageFill = 'coverage-fill';
  static const coverageHalo = 'coverage-halo';
  static const accuracy = 'origin-accuracy';
  static const cluster = 'aeds-cluster';
  static const aedPin = 'aeds-pin';
  static const aedPill = 'aeds-pill';
  static const selectedPin = 'selected-pin';
  static const selectedPill = 'selected-pill';
  static const halo = 'me-halo';

  /// A suggested AED site; tapping it highlights it in the list.
  static const placementSite = 'placement-site';

  /// Tapping one of these opens the AED (pins and their walking-time pills).
  static const aedTargets = [selectedPin, selectedPill, aedPin, aedPill];
}

/// Accuracy area opacity right after a GPS fix; it then fades to 0.
const accuracyOpacity = 0.12;

const emptyCollection = {'type': 'FeatureCollection', 'features': <Object>[]};

String _css(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

Map<String, Object> _feature(Map<String, Object?> properties, List<double> coordinates) => {
  'type': 'Feature',
  'properties': properties,
  'geometry': {'type': 'Point', 'coordinates': coordinates},
};

Map<String, Object> featureCollection(Iterable<Map<String, Object>> features) => {
  'type': 'FeatureCollection',
  'features': features.toList(),
};

Map<String, Object> pointFeature(Map<String, Object?> properties, double lng, double lat) =>
    _feature(properties, [lng, lat]);

Future<void> setSourceData(StyleManager style, String id, Object data) =>
    style.setStyleSourceProperty(id, 'data', jsonEncode(data));

const _overlap = {'icon-allow-overlap': true, 'icon-ignore-placement': true};
const _lineRound = {'line-join': 'round', 'line-cap': 'round'};
final _available = [
  '>',
  ['get', 'available'],
  0,
];

/// Pin: the image's bottom center is the pin tip. Pill: right of the pin, as on web (top 4, left pin + 8).
Map<String, Object> _pinLayer(String id, String source, [List<Object>? filter]) => {
  'id': id,
  'type': 'symbol',
  'source': source,
  'filter': ?filter,
  'layout': {
    ..._overlap,
    'icon-image': ['get', 'pin'],
    'icon-anchor': 'bottom',
  },
};

Map<String, Object> _pillLayer(String id, String source, List<Object> filter) => {
  'id': id,
  'type': 'symbol',
  'source': source,
  'filter': filter,
  'layout': {
    ..._overlap,
    'icon-image': ['get', 'pill'],
    'icon-anchor': 'top-left',
    'icon-offset': [24 - _pillMargin, -36 - _pillMargin],
  },
};

List<Object> _meKind(String kind) => [
  '==',
  ['get', 'kind'],
  kind,
];

final _notSelected = [
  '!=',
  ['get', 'sel'],
  1,
];

final _selected = [
  '==',
  ['get', 'sel'],
  1,
];

/// A suggested site's disc: 32 wide, 40 when picked; the 3-wide ring is drawn outside the radius.
List<Object> _siteRadius(double extra) => ['case', _selected, 17 + extra, 13 + extra];

final _appLayers = <Map<String, Object>>[
  {
    'id': 'warsaw-boundary',
    'type': 'line',
    'source': MapSource.boundary,
    'slot': 'middle',
    'paint': {
      'line-color': _css(AppColors.borderControl),
      'line-width': 2,
      'line-dasharray': [3, 2],
    },
  },
  // Gaps are red hatching; the white halos of the covered areas are drawn above them.
  {
    'id': MapLayer.coverageFill,
    'type': 'fill',
    'source': MapSource.coverage,
    'slot': 'middle',
    'filter': [
      '!=',
      ['get', 'kind'],
      'covered',
    ],
    'paint': {'fill-pattern': 'hatch-gap', 'fill-antialias': false},
  },
  // White circles around the AEDs that count: soft white fill and a clear outline.
  {
    'id': MapLayer.coverageHalo,
    'type': 'fill',
    'source': MapSource.coverage,
    'slot': 'middle',
    'filter': [
      '==',
      ['get', 'kind'],
      'covered',
    ],
    'paint': {'fill-color': '#ffffff', 'fill-opacity': 0.55, 'fill-outline-color': '#ffffff'},
  },
  {
    'id': '${MapLayer.coverageHalo}-edge',
    'type': 'line',
    'source': MapSource.coverage,
    'slot': 'middle',
    'filter': [
      '==',
      ['get', 'kind'],
      'covered',
    ],
    'paint': {'line-color': '#ffffff', 'line-width': 3, 'line-opacity': 0.95},
  },
  // Reach of the suggested AED sites: the radius used for the coverage numbers, dashed green.
  {
    'id': '${MapSource.placementReach}-fill',
    'type': 'fill',
    'source': MapSource.placementReach,
    'slot': 'middle',
    'paint': {'fill-color': _css(AppColors.accent), 'fill-opacity': 0.14},
  },
  {
    'id': '${MapSource.placementReach}-line',
    'type': 'line',
    'source': MapSource.placementReach,
    'slot': 'middle',
    'paint': {
      'line-color': _css(AppColors.accent),
      'line-width': 2,
      'line-dasharray': [2, 2],
    },
  },
  // Starts hidden; the map view shows it briefly after each fix and lets it fade.
  {
    'id': MapLayer.accuracy,
    'type': 'fill',
    'source': MapSource.accuracy,
    'slot': 'top',
    'paint': {
      'fill-color': _css(AppColors.location),
      'fill-opacity': 0,
      'fill-opacity-transition': {'duration': 1200, 'delay': 0},
      'fill-outline-color': _css(AppColors.location),
    },
  },
  // DESIGN.md §7: 5-wide green line over a white casing 9 wide.
  {
    'id': 'route-casing',
    'type': 'line',
    'source': MapSource.route,
    'slot': 'top',
    'layout': _lineRound,
    'paint': {'line-color': _css(AppColors.surface), 'line-width': 9},
  },
  {
    'id': 'route-line',
    'type': 'line',
    'source': MapSource.route,
    'slot': 'top',
    'layout': _lineRound,
    'paint': {'line-color': _css(AppColors.accent), 'line-width': 5},
  },
  // Markers sit above the whole style, like HTML markers. Clusters: the count in a circle, green when at
  // least one AED in it is available now; a tap zooms in.
  {
    'id': '${MapLayer.cluster}-shadow',
    'type': 'circle',
    'source': MapSource.aeds,
    'filter': ['has', 'point_count'],
    'paint': {
      'circle-radius': _clusterRadius(6),
      'circle-color': 'rgba(23, 35, 29, 0.1)',
      'circle-blur': 0.5,
      'circle-translate': [0, 2],
    },
  },
  {
    'id': MapLayer.cluster,
    'type': 'circle',
    'source': MapSource.aeds,
    'filter': ['has', 'point_count'],
    'paint': {
      'circle-radius': _clusterRadius(0),
      'circle-color': ['case', _available, _css(AppColors.accentSoft), _css(AppColors.surface)],
      'circle-stroke-width': 2,
      'circle-stroke-color': ['case', _available, _css(AppColors.accent), _css(AppColors.borderControl)],
    },
  },
  {
    'id': '${MapLayer.cluster}-count',
    'type': 'symbol',
    'source': MapSource.aeds,
    'filter': ['has', 'point_count'],
    'layout': {
      'text-field': [
        'to-string',
        ['get', 'point_count'],
      ],
      // Mapbox hosts no Noto Sans; Open Sans shares its design and digits.
      'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
      'text-size': 15,
      'text-allow-overlap': true,
      'text-ignore-placement': true,
    },
    'paint': {
      'text-color': ['case', _available, _css(AppColors.accent), _css(AppColors.textPrimary)],
    },
  },
  _pinLayer(MapLayer.aedPin, MapSource.aeds, [
    'all',
    [
      '!',
      ['has', 'point_count'],
    ],
    _notSelected,
  ]),
  _pillLayer(MapLayer.aedPill, MapSource.aeds, [
    'all',
    ['has', 'pill'],
    _notSelected,
  ]),
  // GPS: blue dot with a soft pulsing halo. A picked start point: a pin, never a GPS dot (DESIGN.md §7).
  {
    'id': MapLayer.halo,
    'type': 'circle',
    'source': MapSource.me,
    'filter': _meKind('dot'),
    'paint': {'circle-radius': 10, 'circle-color': _css(AppColors.location), 'circle-opacity': 0.4},
  },
  {
    'id': 'me-dot',
    'type': 'symbol',
    'source': MapSource.me,
    'filter': _meKind('dot'),
    'layout': {..._overlap, 'icon-image': MarkerImages.dot},
  },
  {
    'id': 'me-pick',
    'type': 'symbol',
    'source': MapSource.me,
    'filter': _meKind('pick'),
    'layout': {
      ..._overlap,
      'icon-image': MarkerImages.pick,
      'icon-anchor': 'bottom',
      'icon-offset': [0, _pickShadow],
    },
  },
  // Navigation: the walker as an arrow pointing along the route, laid flat on the map.
  {
    'id': 'me-arrow',
    'type': 'symbol',
    'source': MapSource.me,
    'filter': _meKind('arrow'),
    'layout': {
      ..._overlap,
      'icon-image': MarkerImages.arrow,
      'icon-rotate': ['get', 'rotation'],
      'icon-rotation-alignment': 'map',
      'icon-pitch-alignment': 'map',
    },
  },
  // The selected AED stays visible even inside a cluster, raised above its neighbours.
  _pinLayer(MapLayer.selectedPin, MapSource.selected),
  _pillLayer(MapLayer.selectedPill, MapSource.selected, ['has', 'pill']),
  // Suggested sites, above the AED markers like the web's: a green numbered disc in a white ring; the one picked
  // in the list is bigger and darker, ringed amber, and drawn on top.
  {
    'id': '${MapLayer.placementSite}-shadow',
    'type': 'circle',
    'source': MapSource.placementSites,
    'layout': {
      'circle-sort-key': ['get', 'sel'],
    },
    'paint': {
      'circle-radius': _siteRadius(4),
      'circle-color': 'rgba(23, 35, 29, 0.4)',
      'circle-blur': 0.5,
      'circle-translate': [0, 2],
    },
  },
  {
    'id': MapLayer.placementSite,
    'type': 'circle',
    'source': MapSource.placementSites,
    'layout': {
      'circle-sort-key': ['get', 'sel'],
    },
    'paint': {
      'circle-radius': _siteRadius(0),
      'circle-color': ['case', _selected, _css(AppColors.accentPressed), _css(AppColors.accent)],
      'circle-stroke-width': 3,
      'circle-stroke-color': ['case', _selected, _css(AppColors.warning), _css(AppColors.surface)],
    },
  },
  {
    'id': '${MapLayer.placementSite}-rank',
    'type': 'symbol',
    'source': MapSource.placementSites,
    'layout': {
      'text-field': [
        'to-string',
        ['get', 'rank'],
      ],
      'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
      'text-size': 16,
      'text-allow-overlap': true,
      'text-ignore-placement': true,
      'symbol-sort-key': ['get', 'sel'],
    },
    'paint': {'text-color': _css(AppColors.surface)},
  },
];

/// 40 wide (min-width on web), 46 for three digits; the stroke is drawn outside the radius.
List<Object> _clusterRadius(double extra) => [
  'case',
  [
    '>=',
    ['get', 'point_count'],
    100,
  ],
  21 + extra,
  18 + extra,
];

Future<void> addAppLayers(StyleManager style, double dpr) async {
  await style.addStyleImage('hatch-gap', dpr, await _hatchPattern(AppColors.danger, dpr), false, [], [], null);
  for (final id in [MarkerImages.dot, MarkerImages.pick, MarkerImages.arrow]) {
    await style.addStyleImage(id, dpr, await MarkerImages.draw(id, dpr), false, [], [], null);
  }
  final boundary = {
    'type': 'Polygon',
    'coordinates': [
      [
        for (final (lng, lat) in warsawBoundary) [lng, lat],
      ],
    ],
  };
  await style.addStyleSource(MapSource.boundary, jsonEncode({'type': 'geojson', 'data': boundary}));
  for (final id in [
    MapSource.coverage,
    MapSource.accuracy,
    MapSource.route,
    MapSource.me,
    MapSource.selected,
    MapSource.placementReach,
    MapSource.placementSites,
  ]) {
    await style.addStyleSource(id, jsonEncode({'type': 'geojson', 'data': emptyCollection}));
  }
  // Single AEDs from zoom 15; a cluster sums `available` (open now) so it can be tinted.
  await style.addStyleSource(
    MapSource.aeds,
    jsonEncode({
      'type': 'geojson',
      'data': emptyCollection,
      'cluster': true,
      'clusterRadius': 48,
      'clusterMaxZoom': 14,
      'clusterProperties': {
        'available': [
          '+',
          ['get', 'available'],
        ],
      },
    }),
  );
  for (final layer in _appLayers) {
    await style.addStyleLayer(jsonEncode(layer), null);
  }
}

/// Translucent fill with diagonal hatching, so gaps never rely on color alone (DESIGN.md §11):
/// a 12-wide tile, 2-wide stripes every 6 along x + y, as on web.
Future<MbxImage> _hatchPattern(Color color, double dpr, {double stripe = 215, double base = 95}) {
  const size = 12.0;
  return MarkerImages._render(const Size(size, size), dpr, (c) {
    c.drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = color.withAlpha(base.round()));
    final paint = Paint()
      ..color = color.withAlpha(stripe.round())
      ..blendMode = BlendMode.src;
    for (var k = 0.0; k < 2 * size; k += 6) {
      c.drawPath(
        Path()
          ..moveTo(k, 0)
          ..lineTo(k + 2, 0)
          ..lineTo(0, k + 2)
          ..lineTo(0, k)
          ..close(),
        paint,
      );
    }
  });
}

const _pillMargin = 6.0;
const _pickShadow = 6.0;
const _shadow = Color(0x1A17231D);

/// Marker bitmaps, named by what they show so each is drawn once.
abstract final class MarkerImages {
  static const dot = 'me-dot';
  static const pick = 'me-pick';
  static const arrow = 'me-arrow';

  static String pin(AedStatus status, {bool selected = false}) =>
      'pin-${status.tone.name}-${status.icon.name}-${selected ? 1 : 0}';

  /// Walking-time pill, shown only with a start point (DESIGN.md §7).
  static String? pill(EtaEntry? eta) => switch (eta) {
    null => null,
    EtaLoading() => 'pill-',
    EtaOk(:final durationSeconds) => 'pill-${formatDuration(durationSeconds)}',
    EtaFailed() => 'pill-—',
  };

  static Future<MbxImage> draw(String id, double dpr) async {
    if (id.startsWith('pin-')) {
      final [_, tone, icon, selected] = id.split('-');
      return _pin(Tone.values.byName(tone), AppIconName.values.byName(icon), selected == '1', dpr);
    }
    if (id.startsWith('pill-')) return _pill(id.substring(5), dpr);
    return switch (id) {
      dot => _render(const Size(32, 32), dpr, (c) => _gpsDot(c, const Offset(16, 16))),
      pick => _pickPin(dpr),
      _ => _arrow(dpr),
    };
  }

  /// The Mapbox plugin decodes PNG; [size] is in logical pixels, drawn at [dpr].
  static Future<MbxImage> _render(Size size, double dpr, void Function(Canvas canvas) paint) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    paint(canvas);
    final (w, h) = ((size.width * dpr).ceil(), (size.height * dpr).ceil());
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return MbxImage(width: w, height: h, data: bytes!.buffer.asUint8List());
  }

  static Future<PictureInfo> _icon(AppIconName name, Color color) => vg.loadPicture(
    SvgAssetLoader(
      name.asset(),
      packageName: 'design_system',
      theme: SvgTheme(currentColor: color),
    ),
    null,
  );

  static void _drawIcon(Canvas canvas, PictureInfo icon, Offset center, double size) {
    canvas
      ..save()
      ..translate(center.dx - size / 2, center.dy - size / 2)
      ..scale(size / icon.size.width)
      ..drawPicture(icon.picture)
      ..restore();
  }

  static Paint _fill(Color color) => Paint()..color = color;

  static Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;

  static final _blur4 = Paint()
    ..color = _shadow
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

  /// Compact AED pin (web .pin): outline in the status color, AED glyph, status badge, pointer.
  /// 52 x 50 with the tip at the bottom center.
  static Future<MbxImage> _pin(Tone tone, AppIconName statusIcon, bool selected, double dpr) async {
    final aed = await _icon(AppIconName.aed, AppColors.textPrimary);
    final badge = await _icon(statusIcon, tone.fg);
    final pin = Rect.fromLTWH(10, 10, 32, 32);
    RRect round(Rect r, double radius) => RRect.fromRectAndRadius(r, Radius.circular(radius));
    return _render(const Size(52, 50), dpr, (c) {
      c.drawRRect(round(pin.shift(const Offset(0, 2)), 10), _blur4);
      // Selected: extra accent outline with a white separator; status colors stay.
      if (selected) {
        c
          ..drawRRect(round(pin.inflate(5), 15), _fill(AppColors.accent))
          ..drawRRect(round(pin.inflate(2), 12), _fill(AppColors.surface));
      }
      c
        ..drawRRect(round(pin, 10), _fill(AppColors.surface))
        ..drawRRect(round(pin.deflate(1), 9), _stroke(tone.fg, 2));
      // Pointer below the pin: a white square turned 45° with its two lower edges outlined.
      const tip = Offset(26, 42);
      final half = 5 * sqrt2, edge = half - sqrt2;
      c
        ..drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy - half)
            ..lineTo(tip.dx + half, tip.dy)
            ..lineTo(tip.dx, tip.dy + half)
            ..lineTo(tip.dx - half, tip.dy)
            ..close(),
          _fill(AppColors.surface),
        )
        ..drawPath(
          Path()
            ..moveTo(tip.dx + edge, tip.dy)
            ..lineTo(tip.dx, tip.dy + edge)
            ..lineTo(tip.dx - edge, tip.dy),
          _stroke(tone.fg, 2),
        );
      _drawIcon(c, aed, pin.center, 20);
      const badgeCenter = Offset(38, 14);
      c
        ..drawCircle(badgeCenter, 10, _fill(AppColors.surface))
        ..drawCircle(badgeCenter, 9, _stroke(tone.fg, 2));
      _drawIcon(c, badge, badgeCenter, 16);
    });
  }

  /// White pill with the walking time ("4 min", "—"), or a grey bar while it loads.
  static Future<MbxImage> _pill(String text, double dpr) async {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTextStyles.small(14, weight: FontWeight.w600).copyWith(height: 20 / 14, color: AppColors.textPrimary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final content = text.isEmpty ? 28.0 : painter.width;
    final body = Rect.fromLTWH(_pillMargin, _pillMargin, content + 16, 24);
    final pill = RRect.fromRectAndRadius(body, const Radius.circular(12));
    return _render(Size(body.width + 2 * _pillMargin, body.height + 2 * _pillMargin), dpr, (c) {
      c
        ..drawRRect(pill.shift(const Offset(0, 2)), _blur4)
        ..drawRRect(pill, _fill(AppColors.surface));
      if (text.isEmpty) {
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(body.left + 8, body.top + 8, 28, 8), const Radius.circular(4)),
          _fill(AppColors.unknownSoft),
        );
      } else {
        painter.paint(c, Offset(body.left + 8, body.top + 2));
      }
    });
  }

  static void _gpsDot(Canvas c, Offset center) {
    c
      ..drawCircle(center.translate(0, 2), 10, _blur4)
      ..drawCircle(center, 10, _fill(AppColors.surface))
      ..drawCircle(center, 7, _fill(AppColors.location));
  }

  /// Map pin glyph in green with a soft drop shadow; its 32 box ends [_pickShadow] above the image bottom.
  static Future<MbxImage> _pickPin(double dpr) async {
    final glyph = await _icon(AppIconName.locationOn, AppColors.accent);
    final shadow = await _icon(AppIconName.locationOn, const Color(0x4017231D));
    return _render(const Size(40, 32 + _pickShadow), dpr, (c) {
      c.saveLayer(null, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2));
      _drawIcon(c, shadow, const Offset(20, 18), 32);
      c.restore();
      _drawIcon(c, glyph, const Offset(20, 16), 32);
    });
  }

  /// Heading arrow (web HeadingMarker): `M12 2.5 20 21l-8-4.2L4 21z` at 56 px, blue with a white edge.
  static Future<MbxImage> _arrow(double dpr) {
    const scale = 56 / 24;
    final path = Path()
      ..moveTo(12, 2.5)
      ..lineTo(20, 21)
      ..lineTo(12, 16.8)
      ..lineTo(4, 21)
      ..close();
    return _render(const Size(68, 68), dpr, (c) {
      c
        ..translate(6, 6)
        ..scale(scale);
      c.drawPath(
        path.shift(const Offset(0, 2 / scale)),
        Paint()
          ..color = const Color(0x4D17231D)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5 / scale),
      );
      c
        ..drawPath(path, _fill(AppColors.location))
        ..drawPath(path, _stroke(AppColors.surface, 1.5)..strokeJoin = StrokeJoin.round);
    });
  }
}
