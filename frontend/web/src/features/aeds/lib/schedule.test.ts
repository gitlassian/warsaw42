import assert from 'node:assert/strict'
import { test } from 'node:test'
import { toSchedule } from './schedule.ts'

const weekly = { weekly: { '1': { state: 'open_intervals' as const, intervals: [[480, 1080]] as [number, number][] } } }

test('unverified or unknown hours stay unknown, like the server', () => {
  assert.deepEqual(toSchedule({ hours_status: '24/7', hours_verified: false, hours: {} }), { kind: 'unknown' })
  assert.deepEqual(toSchedule({ hours_status: 'unknown', hours_verified: true, hours: {} }), { kind: 'unknown' })
})

test('verified 24/7 is always open', () => {
  assert.deepEqual(toSchedule({ hours_status: '24/7', hours_verified: true, hours: {} }), { kind: 'always_open' })
})

test('weekly minutes become HH:MM; closed days are empty, missing days unknown', () => {
  const hours = {
    weekly: {
      ...weekly.weekly,
      '6': { state: 'closed' as const, intervals: [] },
      '7': { state: 'open_intervals' as const, intervals: [[0, 1440]] as [number, number][] },
    },
  }
  assert.deepEqual(toSchedule({ hours_status: 'scheduled', hours_verified: true, hours }), {
    kind: 'weekly',
    days: [[['08:00', '18:00']], null, null, null, null, [], [['00:00', '24:00']]],
  })
})
