import type { PlacementData, PlacementMode, PlacementPick, PlacementView } from '../models/placement'

/** Slots are half-hour steps from Monday 00:00; `day` 0 = Monday, as in `warsawClock`. */
export const slotIndex = (day: number, minutes: number, slotMinutes: number) =>
  day * Math.round(1440 / slotMinutes) + Math.floor(minutes / slotMinutes)

/** The `count` best steps for the slot at `at`, with the totals they add. */
export function placementView(
  data: PlacementData,
  at: { day: number; minutes: number },
  mode: PlacementMode,
  count: number,
): PlacementView {
  const slot = data.slots[slotIndex(at.day, at.minutes, data.slot_minutes)]
  const steps = (mode === 'new' ? slot.n : slot.v).slice(0, count)
  const picks = steps.map(([index, gain, gain65, cumulativePct], i): PlacementPick => {
    if (mode === 'new') {
      const [lng, lat, address] = data.candidates[index]
      return { rank: i + 1, lng, lat, title: address, address, gain, gain65, cumulativePct }
    }
    const [, name, address, lng, lat] = data.aeds[index]
    return { rank: i + 1, lng, lat, title: name, address, gain, gain65, cumulativePct }
  })
  const coveredPctAfter = picks.at(-1)?.cumulativePct ?? slot.c
  return {
    slot,
    picks,
    gainPct: Math.round((coveredPctAfter - slot.c) * 10) / 10,
    gainPeople: picks.reduce((sum, p) => sum + p.gain, 0),
    coveredPctAfter,
  }
}
