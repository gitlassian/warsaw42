import assert from 'node:assert/strict'
import { test } from 'node:test'
import { aedFromRow, scheduleFromRow, type AedRow } from './fromRow.ts'

const base: AedRow = {
  id: 'b1', object_name: 'Urząd', full_address: 'Rakowiecka 25/27, 02-517 Warszawa', lon: 21.01, lat: 52.2,
  in_building: true, floor: 0, access_instructions: null, public_access: 'public', operational_status: 'unknown',
  hours_text: 'Pn 8-18', hours_status: 'scheduled', hours_verified: true, hours: {}, photo_path: '622.webp',
  source: 'city', hours_source: 'city',
}

test('minutes become HH:MM and ISO weekdays become indexes from Monday', () => {
  const schedule = scheduleFromRow({
    ...base,
    hours: { weekly: { 1: { state: 'open_intervals', intervals: [[480, 1080]] }, 3: { state: 'open_intervals', intervals: [[0, 1440]] } } },
  })
  assert.deepEqual(schedule, {
    kind: 'weekly',
    days: [[['08:00', '18:00']], null, [['00:00', '24:00']], null, null, null, null],
  })
})

test('closed is an empty list, an omitted day stays unknown', () => {
  const schedule = scheduleFromRow({ ...base, hours: { weekly: { 6: { state: 'closed', intervals: [] }, 7: { state: 'unknown', intervals: [] } } } })
  assert.deepEqual(schedule, { kind: 'weekly', days: [null, null, null, null, null, [], null] })
})

test('unverified or unparsed hours are unknown, 24/7 is always open', () => {
  assert.deepEqual(scheduleFromRow({ ...base, hours_verified: false }), { kind: 'unknown' })
  assert.deepEqual(scheduleFromRow({ ...base, hours_status: 'unknown' }), { kind: 'unknown' })
  assert.deepEqual(scheduleFromRow({ ...base, hours_status: '24/7', hours: {} }), { kind: 'always_open' })
  assert.deepEqual(scheduleFromRow({ ...base, hours: { weekly: {} } }), { kind: 'unknown' })
})

test('unverified hours keep their intervals only as a draft', () => {
  const row = { ...base, hours_verified: false, hours: { weekly: { 1: { state: 'open_intervals', intervals: [[360, 1080]] as [number, number][] } } } }
  const aed = aedFromRow(row, (f) => f)
  assert.deepEqual(aed.schedule, { kind: 'unknown' })
  assert.deepEqual(aed.unverifiedSchedule, { kind: 'weekly', days: [[['06:00', '18:00']], null, null, null, null, null, null] })
  assert.equal(aedFromRow(base, (f) => f).unverifiedSchedule, null)
})

test('row maps to the Aed model with a photo link', () => {
  const aed = aedFromRow(base, (f) => `https://x/${f}`)
  assert.deepEqual(aed.location, { lng: 21.01, lat: 52.2 })
  assert.equal(aed.venueName, 'Urząd')
  assert.equal(aed.indoor, true)
  assert.equal(aed.photoUrl, 'https://x/622.webp')
  assert.equal(aed.source, 'city')
  assert.equal(aedFromRow({ ...base, photo_path: null }, (f) => f).photoUrl, null)
})
