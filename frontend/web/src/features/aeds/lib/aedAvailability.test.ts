import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Aed } from '../models/aed.ts'
import { aedAvailability, passesFilters } from './aedAvailability.ts'

const base: Aed = {
  id: '1', location: { lng: 21, lat: 52.2 }, venueName: 'x', address: 'y', entrance: null, indoor: true, floor: null,
  publicAccess: 'public', operationalStatus: 'unknown', schedule: { kind: 'unknown' }, sourceHours: null, sourceNote: null,
}
const office: Aed = { ...base, schedule: { kind: 'weekly', days: [[['08:00', '16:00']], [['08:00', '16:00']], [['08:00', '16:00']], [['08:00', '16:00']], [['08:00', '16:00']], [], []] } }
const monday = (hhmm: string) => new Date(`2026-10-19T${hhmm}:00+02:00`)

test('open, closed, and unknown hours (no information means unavailable)', () => {
  assert.equal(aedAvailability(office, monday('10:00')), 'available')
  assert.equal(aedAvailability(office, monday('20:00')), 'unavailable')
  assert.equal(aedAvailability(office, new Date('2026-10-17T12:00:00+02:00')), 'unavailable') // Saturday: closed
  assert.equal(aedAvailability(base, monday('10:00')), 'unavailable')
  assert.equal(aedAvailability({ ...base, schedule: { kind: 'always_open' } }, monday('03:00')), 'available')
})

test('a broken, restricted or unconfirmed device is unavailable', () => {
  assert.equal(aedAvailability({ ...office, operationalStatus: 'confirmed_unavailable' }, monday('10:00')), 'unavailable')
  assert.equal(aedAvailability({ ...office, publicAccess: 'restricted' }, monday('10:00')), 'unavailable')
  assert.equal(aedAvailability({ ...office, publicAccess: 'unknown' }, monday('10:00')), 'unavailable')
})

test('selected groups are shown, and no selection shows everything', () => {
  const none = { available: false, unavailable: false }
  assert.equal(passesFilters(base, monday('10:00'), none), true)
  assert.equal(passesFilters(office, monday('20:00'), none), true)
  assert.equal(passesFilters(office, monday('10:00'), { ...none, available: true }), true)
  assert.equal(passesFilters(office, monday('20:00'), { ...none, available: true }), false)
  assert.equal(passesFilters(base, monday('10:00'), { ...none, available: true }), false)
  assert.equal(passesFilters(base, monday('10:00'), { ...none, unavailable: true }), true)
  assert.equal(passesFilters(office, monday('20:00'), { ...none, unavailable: true }), true)
})
