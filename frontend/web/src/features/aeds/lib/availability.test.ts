import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Schedule } from '../models/aed.ts'
import { evaluateHours, isOpenThrough } from './availability.ts'

// The PLAN.md §5 example: Mon 08–18, Tue–Fri 08–16, weekend not stated.
const office: Schedule = {
  kind: 'weekly',
  days: [[['08:00', '18:00']], [['08:00', '16:00']], [['08:00', '16:00']], [['08:00', '16:00']], [['08:00', '16:00']], null, null],
}
const at = (iso: string) => new Date(iso)

test('open with closing time', () => {
  assert.deepEqual(evaluateHours(office, at('2026-10-19T10:00:00+02:00')), { state: 'open', until: '18:00' })
})

test('closed before and after hours, with the next opening the same day', () => {
  assert.deepEqual(evaluateHours(office, at('2026-10-19T07:00:00+02:00')), { state: 'closed', opensAt: '08:00' })
  assert.deepEqual(evaluateHours(office, at('2026-10-19T18:00:00+02:00')), { state: 'closed', opensAt: null })
})

test('omitted weekend stays unknown', () => {
  assert.deepEqual(evaluateHours(office, at('2026-10-17T12:00:00+02:00')), { state: 'unknown' })
})

test('evaluates in Warsaw time, not UTC', () => {
  // 06:30 UTC on Monday = 08:30 in Warsaw (CEST).
  assert.equal(evaluateHours(office, at('2026-10-19T06:30:00Z')).state, 'open')
})

test('closing before arrival plus buffer is rejected', () => {
  assert.equal(isOpenThrough(office, at('2026-10-19T17:50:00+02:00'), at('2026-10-19T17:59:00+02:00')), true)
  assert.equal(isOpenThrough(office, at('2026-10-19T17:55:00+02:00'), at('2026-10-19T18:01:00+02:00')), false)
})

test('overnight hours chain across midnight', () => {
  const night: Schedule = { kind: 'weekly', days: [[['20:00', '24:00']], [['00:00', '06:00']], null, null, null, null, null] }
  assert.equal(isOpenThrough(night, at('2026-10-19T23:58:00+02:00'), at('2026-10-20T00:03:00+02:00')), true)
})

test('24/7 and unknown schedules', () => {
  assert.deepEqual(evaluateHours({ kind: 'always_open' }, new Date()), { state: 'open', until: null })
  assert.equal(isOpenThrough({ kind: 'unknown' }, new Date(), new Date()), false)
})
