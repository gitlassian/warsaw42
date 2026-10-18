import 'package:defiwawa/features/placement/models/placement.dart';

/// Slots are half-hour steps from Monday 00:00; `day` 0 = Monday, as in `warsawClock`.
int slotIndex(int day, int minutes, int slotMinutes) => day * (1440 / slotMinutes).round() + minutes ~/ slotMinutes;

/// The [count] best steps for the slot at [day] and [minutes], with the totals they add.
PlacementView placementView(
  PlacementData data, {
  required int day,
  required int minutes,
  required PlacementMode mode,
  required int count,
}) {
  final slot = data.slots[slotIndex(day, minutes, data.slotMinutes)];
  final steps = (mode == PlacementMode.newSites ? slot.newSites : slot.convert).take(count);
  final picks = [
    for (final (i, step) in steps.indexed)
      if (mode == PlacementMode.newSites)
        PlacementPick(
          rank: i + 1,
          lng: data.candidates[step.index].lng,
          lat: data.candidates[step.index].lat,
          title: data.candidates[step.index].address,
          address: data.candidates[step.index].address,
          gain: step.gain,
          gain65: step.gain65,
          cumulativePct: step.cumulativePct,
        )
      else
        PlacementPick(
          rank: i + 1,
          lng: data.aeds[step.index].lng,
          lat: data.aeds[step.index].lat,
          title: data.aeds[step.index].name,
          address: data.aeds[step.index].address,
          gain: step.gain,
          gain65: step.gain65,
          cumulativePct: step.cumulativePct,
        ),
  ];
  final coveredPctAfter = picks.isEmpty ? slot.coveredPct : picks.last.cumulativePct;
  return PlacementView(
    slot: slot,
    picks: picks,
    gainPct: ((coveredPctAfter - slot.coveredPct) * 10).round() / 10,
    gainPeople: picks.fold(0, (sum, p) => sum + p.gain),
    coveredPctAfter: coveredPctAfter,
  );
}
