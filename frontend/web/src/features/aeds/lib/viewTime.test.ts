import assert from 'node:assert/strict'
import { test } from 'node:test'
import { nextWarsawWeekday } from './viewTime.ts'

const SAT_AFTERNOON = new Date('2026-10-17T15:00:00+02:00') // Saturday

test('same weekday means today', () => {
  assert.equal(nextWarsawWeekday(5, 3 * 60, SAT_AFTERNOON).toISOString(), new Date('2026-10-17T03:00:00+02:00').toISOString())
})

test('other weekdays resolve to the next such day', () => {
  assert.equal(nextWarsawWeekday(0, 10 * 60, SAT_AFTERNOON).toISOString(), new Date('2026-10-19T10:00:00+02:00').toISOString())
  assert.equal(nextWarsawWeekday(4, 23 * 60 + 45, SAT_AFTERNOON).toISOString(), new Date('2026-10-23T23:45:00+02:00').toISOString())
})

test('uses the winter offset after the clocks go back on 25.10.2026', () => {
  const sunday = new Date('2026-10-25T12:00:00+01:00')
  assert.equal(nextWarsawWeekday(0, 10 * 60, sunday).toISOString(), new Date('2026-10-26T10:00:00+01:00').toISOString())
})

test('the Warsaw date, not the UTC date, picks the day', () => {
  // 23:30 UTC on Saturday is already 01:30 on Sunday in Warsaw.
  const lateSaturdayUtc = new Date('2026-10-17T23:30:00Z')
  assert.equal(nextWarsawWeekday(6, 8 * 60, lateSaturdayUtc).toISOString(), new Date('2026-10-18T08:00:00+02:00').toISOString())
})
