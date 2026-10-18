import 'package:defiwawa/features/coverage/lib/coverage_geometry.dart';
import 'package:defiwawa/features/discovery/lib/geocoding.dart';
import 'package:defiwawa/features/discovery/models/routing.dart';
import 'package:defiwawa/features/navigation/lib/progress.dart';
import 'package:defiwawa/shared/geo/geo.dart';
import 'package:flutter_test/flutter_test.dart';

// Ports of the web tests (geocoding, navigation progress, coverage geometry).

void main() {
  group('geocoding', () {
    bool insideWarsaw(LngLat p) => p.lng < 21.2;

    test('keeps hits inside the city, starts at the routable point, shortens the place line', () {
      final hits = parseAddressHits({
        'features': [
          {
            'id': 'a',
            'properties': {
              'name': 'Marszałkowska 10/16',
              'place_formatted': '00-590 Warszawa, województwo mazowieckie, Polska',
              'coordinates': {
                'longitude': 21.0207,
                'latitude': 52.2156,
                'routable_points': [
                  {'longitude': 21.0205, 'latitude': 52.2155},
                ],
              },
            },
          },
          {
            'id': 'b',
            'properties': {
              'name': 'Marszałkowska 10',
              'place_formatted': '05-200 Wołomin, województwo mazowieckie, Polska',
              'coordinates': {'longitude': 21.2496, 'latitude': 52.3237},
            },
          },
        ],
      }, insideWarsaw);
      expect(hits, [
        const AddressHit(
          id: 'a',
          name: 'Marszałkowska 10/16',
          detail: '00-590 Warszawa',
          location: LngLat(21.0205, 52.2155),
        ),
      ]);
      expect(parseAddressHits({}, insideWarsaw), isEmpty);
    });

    test('names the city once a house number is typed', () {
      expect(geocodingQuery('Marszałk'), 'Marszałk');
      expect(geocodingQuery('Marszałkowska 10'), 'Marszałkowska 10, Warszawa');
      expect(geocodingQuery('Złota 44 Warszawa'), 'Złota 44 Warszawa');
    });
  });

  group('navigation progress', () {
    // An L-shaped route: ~111 m north, then ~68 m east (at Warsaw's latitude).
    const coordinates = [
      [21.0, 52.2],
      [21.0, 52.201],
      [21.001, 52.201],
    ];
    RouteStep step(double lng, double lat, String type) => RouteStep(
      instruction: type,
      maneuverType: type,
      maneuverModifier: null,
      street: null,
      location: LngLat(lng, lat),
      distanceM: 0,
      durationSeconds: 0,
    );
    final steps = [step(21.0, 52.2, 'depart'), step(21.0, 52.201, 'turn'), step(21.001, 52.201, 'arrive')];
    final plan = planRoute(coordinates, steps);

    test('steps are placed along the route line in walking order', () {
      expect(plan.stepAlongM[0], 0);
      expect(plan.stepAlongM[1], closeTo(111.3, 1));
      expect(plan.totalM, closeTo(179.6, 1));
      expect(plan.stepAlongM[2], plan.totalM);
    });

    test('the walker is projected onto the nearest segment', () {
      final progress = locateOnRoute(plan, const LngLat(21.0001, 52.2005));
      expect(progress.alongM, closeTo(55.7, 1));
      expect(progress.offRouteM, closeTo(6.8, 1));
      expect(isOffRoute(progress), false);
    });

    test('the upcoming maneuver advances once it is behind the walker', () {
      expect(upcomingStep(plan, 0), 1);
      expect(upcomingStep(plan, 100), 1);
      expect(upcomingStep(plan, 120), 2);
    });

    test('off route beyond 40 m or the GPS accuracy; arrival within 20 m of the end', () {
      expect(isOffRoute((alongM: 0, offRouteM: 50)), true);
      expect(isOffRoute((alongM: 0, offRouteM: 50), 80), false);
      expect(hasArrived(plan, (alongM: plan.totalM - 10, offRouteM: 5)), true);
      expect(hasArrived(plan, (alongM: plan.totalM - 50, offRouteM: 5)), false);
    });

    test('points along the line are interpolated and clamped', () {
      expect(pointAlong(plan, plan.stepAlongM[1] / 2).lat, closeTo(52.2005, 1e-6));
      expect(pointAlong(plan, -5), const LngLat(21.0, 52.2));
      expect(pointAlong(plan, 1e6), const LngLat(21.001, 52.201));
    });

    test('heading follows the route: north on the first leg, east on the second', () {
      expect(headingAt(plan, 0), lessThan(1));
      expect(headingAt(plan, 130), closeTo(90, 1));
      // Near the corner the look-ahead already turns the map towards the next leg.
      expect(headingAt(plan, 100), inExclusiveRange(10, 80));
    });
  });

  group('coverage geometry', () {
    // About 2.2 km x 2.2 km box around 21.0, 52.2.
    const box = [(20.985, 52.19), (21.015, 52.19), (21.015, 52.21), (20.985, 52.21), (20.985, 52.19)];
    List<Object?> kinds(List<Map<String, Object>> areas) => [for (final a in areas) (a['properties'] as Map)['kind']];

    test('no eligible AED is all gap; a circle leaves the rest as gap; a large one covers all', () {
      expect(kinds(coverageAreas(box, [], 500)), ['gap']);
      final areas = coverageAreas(box, [(id: 'a', lng: 21.0, lat: 52.2)], 500);
      expect(kinds(areas), ['gap', 'covered']);
      // The gap is the box with the circle as its hole.
      final gap = ((areas.first['geometry'] as Map)['coordinates'] as List).single as List;
      expect(gap, hasLength(2));
      expect(kinds(coverageAreas(box, [(id: 'a', lng: 21.0, lat: 52.2)], 5000)), ['covered']);
    });

    test('overlapping circles merge into one covered area', () {
      final areas = coverageAreas(box, [(id: 'a', lng: 21.0, lat: 52.2), (id: 'b', lng: 21.003, lat: 52.2)], 300);
      final covered = (areas.last['geometry'] as Map)['coordinates'] as List;
      expect(covered, hasLength(1));
    });

    test('nearest site and its distance', () {
      final near = nearestSite(21.0, 52.2, [(id: 'far', lng: 21.01, lat: 52.2), (id: 'near', lng: 21.001, lat: 52.2)]);
      expect(near?.site.id, 'near');
      expect(near!.distanceM, inExclusiveRange(60, 80));
      expect(nearestSite(21, 52.2, []), isNull);
    });
  });
}
