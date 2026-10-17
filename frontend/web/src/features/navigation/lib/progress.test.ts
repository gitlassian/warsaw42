import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { LineString } from 'geojson'
import type { RouteStep } from '../../discovery/models/routing'
import { hasArrived, headingAt, isOffRoute, locateOnRoute, planRoute, pointAlong, upcomingStep } from './progress.ts'

// An L-shaped route: ~111 m north, then ~68 m east (at Warsaw's latitude).
const geometry: LineString = {
  type: 'LineString',
  coordinates: [
    [21.0, 52.2],
    [21.0, 52.201],
    [21.001, 52.201],
  ],
}

const step = (lng: number, lat: number, maneuverType: string): RouteStep => ({
  instruction: maneuverType,
  maneuverType,
  maneuverModifier: null,
  street: null,
  location: { lng, lat },
  distanceM: 0,
  durationSeconds: 0,
})

const steps = [step(21.0, 52.2, 'depart'), step(21.0, 52.201, 'turn'), step(21.001, 52.201, 'arrive')]

test('steps are placed along the route line in walking order', () => {
  const plan = planRoute(geometry, steps)
  assert.equal(plan.stepAlongM[0], 0)
  assert.ok(Math.abs(plan.stepAlongM[1] - 111.3) < 1)
  assert.ok(Math.abs(plan.totalM - 179.6) < 1)
  assert.equal(plan.stepAlongM[2], plan.totalM)
})

test('the walker is projected onto the nearest segment', () => {
  const plan = planRoute(geometry, steps)
  // Halfway up the first leg, ~7 m east of it.
  const progress = locateOnRoute(plan, { lng: 21.0001, lat: 52.2005 })
  assert.ok(Math.abs(progress.alongM - 55.7) < 1)
  assert.ok(Math.abs(progress.offRouteM - 6.8) < 1)
  assert.equal(isOffRoute(progress), false)
})

test('the upcoming maneuver advances once it is behind the walker', () => {
  const plan = planRoute(geometry, steps)
  assert.equal(upcomingStep(plan, 0), 1)
  assert.equal(upcomingStep(plan, 100), 1)
  assert.equal(upcomingStep(plan, 120), 2)
})

test('off route beyond 40 m or beyond the GPS accuracy, whichever is larger', () => {
  assert.equal(isOffRoute({ alongM: 0, offRouteM: 50 }), true)
  assert.equal(isOffRoute({ alongM: 0, offRouteM: 50 }, 80), false)
})

test('arrival within 20 m of the end of the line', () => {
  const plan = planRoute(geometry, steps)
  assert.equal(hasArrived(plan, { alongM: plan.totalM - 10, offRouteM: 5 }), true)
  assert.equal(hasArrived(plan, { alongM: plan.totalM - 50, offRouteM: 5 }), false)
})

test('points along the line are interpolated and clamped', () => {
  const plan = planRoute(geometry, steps)
  const half = pointAlong(plan, plan.stepAlongM[1] / 2)
  assert.ok(Math.abs(half.lat - 52.2005) < 1e-6)
  assert.deepEqual(pointAlong(plan, -5), { lng: 21.0, lat: 52.2 })
  assert.deepEqual(pointAlong(plan, 1e6), { lng: 21.001, lat: 52.201 })
})

test('heading follows the route: north on the first leg, east on the second', () => {
  const plan = planRoute(geometry, steps)
  assert.ok(headingAt(plan, 0) < 1)
  assert.ok(Math.abs(headingAt(plan, 130) - 90) < 1)
  // Near the corner the look-ahead already turns the map towards the next leg.
  const corner = headingAt(plan, 100)
  assert.ok(corner > 10 && corner < 80)
})
