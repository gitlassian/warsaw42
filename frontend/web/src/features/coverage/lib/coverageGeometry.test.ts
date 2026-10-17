import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Polygon } from 'geojson'
import { coverageAreas, nearestSite } from './coverageGeometry.ts'

// About 2.2 km x 2.2 km box around 21.0, 52.2.
const box: Polygon = {
  type: 'Polygon',
  coordinates: [[[20.985, 52.19], [21.015, 52.19], [21.015, 52.21], [20.985, 52.21], [20.985, 52.19]]],
}
const kinds = (areas: ReturnType<typeof coverageAreas>) => areas.map((a) => a.properties.kind)

test('a city with no eligible AED is all gap', () => {
  assert.deepEqual(kinds(coverageAreas(box, [], 500)), ['gap'])
})

test('a circle makes a covered area and leaves the rest as gap', () => {
  const areas = coverageAreas(box, [{ id: 'a', lng: 21.0, lat: 52.2 }], 500)
  assert.deepEqual(kinds(areas), ['gap', 'covered'])
})


test('a radius that covers the whole box leaves no gap', () => {
  const areas = coverageAreas(box, [{ id: 'a', lng: 21.0, lat: 52.2 }], 5000)
  assert.deepEqual(kinds(areas), ['covered'])
})

test('nearest site and its distance', () => {
  const near = nearestSite(21.0, 52.2, [{ id: 'far', lng: 21.01, lat: 52.2 }, { id: 'near', lng: 21.001, lat: 52.2 }])
  assert.equal(near?.site.id, 'near')
  assert.ok(near && near.distanceM > 60 && near.distanceM < 80)
  assert.equal(nearestSite(21, 52.2, []), null)
})
