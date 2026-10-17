import assert from 'node:assert/strict'
import { test } from 'node:test'
import { geocodingQuery, parseAddressHits } from './geocoding.ts'

const insideWarsaw = ({ lng }: { lng: number; lat: number }) => lng < 21.2

test('keeps hits inside the city, starts at the routable point, shortens the place line', () => {
  const hits = parseAddressHits(
    {
      features: [
        {
          id: 'a',
          properties: {
            name: 'Marszałkowska 10/16',
            place_formatted: '00-590 Warszawa, województwo mazowieckie, Polska',
            coordinates: { longitude: 21.0207, latitude: 52.2156, routable_points: [{ longitude: 21.0205, latitude: 52.2155 }] },
          },
        },
        {
          id: 'b',
          properties: {
            name: 'Marszałkowska 10',
            place_formatted: '05-200 Wołomin, województwo mazowieckie, Polska',
            coordinates: { longitude: 21.2496, latitude: 52.3237 },
          },
        },
      ],
    },
    insideWarsaw,
  )
  assert.deepEqual(hits, [
    { id: 'a', name: 'Marszałkowska 10/16', detail: '00-590 Warszawa', location: { lng: 21.0205, lat: 52.2155 } },
  ])
})

test('names the city once a house number is typed', () => {
  assert.equal(geocodingQuery('Marszałk'), 'Marszałk')
  assert.equal(geocodingQuery('Marszałkowska 10'), 'Marszałkowska 10, Warszawa')
  assert.equal(geocodingQuery('Złota 44 Warszawa'), 'Złota 44 Warszawa')
})

test('no features means no hits', () => {
  assert.deepEqual(parseAddressHits({}, insideWarsaw), [])
})
