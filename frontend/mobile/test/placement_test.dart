import 'package:flutter_test/flutter_test.dart';

import 'package:defiwawa/shared/lib/format.dart';
import 'package:defiwawa/features/placement/lib/placement_slots.dart';
import 'package:defiwawa/features/placement/models/placement.dart';

// Port of frontend/web/src/features/placement/lib/placementSlots.test.ts.
final _data = PlacementData.fromJson({
  'radius_m': 500,
  'slot_minutes': 30,
  'cost_per_aed_pln': 10000,
  'cost_basis': 'test',
  'candidates': [
    [21.0, 52.2, 'Marszałkowska 1, 00-001 Warszawa'],
    [21.1, 52.3, 'Długa 2, 00-002 Warszawa'],
  ],
  'aeds': [
    ['622', 'Urząd', 'Rakowiecka 25/27', 21.01, 52.21],
  ],
  'slots': [
    for (var i = 0; i < 336; i++)
      i == 0
          ? {
              'a': 3,
              'c': 20,
              'u': 800,
              'u65': 150,
              'n': [
                [1, 500, 90, 30],
                [0, 200, 40, 35],
              ],
              'v': [
                [0, 300, 60, 25],
              ],
            }
          : {'a': 0, 'c': 0, 'u': 0, 'u65': 0, 'n': <Object>[], 'v': <Object>[]},
  ],
});

void main() {
  test('slot index counts half hours from Monday 00:00', () {
    expect(slotIndex(0, 0, 30), 0);
    expect(slotIndex(0, 29, 30), 0);
    expect(slotIndex(1, 3 * 60, 30), 54);
    expect(slotIndex(6, 23 * 60 + 59, 30), 335);
  });

  test('new addresses: ranked picks with the percentage points they add', () {
    final view = placementView(_data, day: 0, minutes: 10, mode: PlacementMode.newSites, count: 2);
    expect(view.picks.map((p) => p.address), ['Długa 2, 00-002 Warszawa', 'Marszałkowska 1, 00-001 Warszawa']);
    expect(view.gainPeople, 700);
    expect(view.gainPct, 15);
    expect(view.coveredPctAfter, 35);
  });

  test('the count cuts the list, and converting names an existing AED', () {
    expect(placementView(_data, day: 0, minutes: 0, mode: PlacementMode.newSites, count: 1).picks, hasLength(1));
    final view = placementView(_data, day: 0, minutes: 0, mode: PlacementMode.convert, count: 5);
    expect(view.picks.first.title, 'Urząd');
    expect(view.gainPct, 5);
  });

  test('an empty slot adds nothing', () {
    final view = placementView(_data, day: 2, minutes: 0, mode: PlacementMode.newSites, count: 10);
    expect([view.picks.length, view.gainPct, view.gainPeople], [0, 0, 0]);
  });

  test('counts group thousands like pl-PL, from five digits on', () {
    expect([formatCount(3612), formatCount(17364), formatCount(1519485)], ['3612', '17 364', '1 519 485']);
  });
}
