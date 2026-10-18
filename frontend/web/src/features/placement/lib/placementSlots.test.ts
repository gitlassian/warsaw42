import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { PlacementData } from '../models/placement.ts'
import { placementView, slotIndex } from './placementSlots.ts'

test('slot index counts half hours from Monday 00:00', () => {
  assert.equal(slotIndex(0, 0, 30), 0)
  assert.equal(slotIndex(0, 29, 30), 0)
  assert.equal(slotIndex(1, 3 * 60, 30), 54)
  assert.equal(slotIndex(6, 23 * 60 + 59, 30), 335)
})

const data = {
  slot_minutes: 30,
  candidates: [[21.0, 52.2, 'Marszałkowska 1, 00-001 Warszawa'], [21.1, 52.3, 'Długa 2, 00-002 Warszawa']],
  aeds: [['622', 'Urząd', 'Rakowiecka 25/27', 21.01, 52.21]],
  slots: Array.from({ length: 336 }, (_, i) =>
    i === 0
      ? { a: 3, c: 20, u: 800, u65: 150, n: [[1, 500, 90, 30], [0, 200, 40, 35]], v: [[0, 300, 60, 25]] }
      : { a: 0, c: 0, u: 0, u65: 0, n: [], v: [] },
  ),
} as unknown as PlacementData

test('new addresses: ranked picks with the percentage points they add', () => {
  const view = placementView(data, { day: 0, minutes: 10 }, 'new', 2)
  assert.deepEqual(view.picks.map((p) => p.address), ['Długa 2, 00-002 Warszawa', 'Marszałkowska 1, 00-001 Warszawa'])
  assert.equal(view.gainPeople, 700)
  assert.equal(view.gainPct, 15)
  assert.equal(view.coveredPctAfter, 35)
})

test('the count cuts the list, and converting names an existing AED', () => {
  assert.equal(placementView(data, { day: 0, minutes: 0 }, 'new', 1).picks.length, 1)
  const view = placementView(data, { day: 0, minutes: 0 }, 'convert', 5)
  assert.equal(view.picks[0].title, 'Urząd')
  assert.equal(view.gainPct, 5)
})

test('an empty slot adds nothing', () => {
  const view = placementView(data, { day: 2, minutes: 0 }, 'new', 10)
  assert.deepEqual([view.picks.length, view.gainPct, view.gainPeople], [0, 0, 0])
})
