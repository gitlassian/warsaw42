import type { FeatureCollection, GeoJSON } from 'geojson'
import type { GeoJSONSource, Map as MapboxMap } from 'mapbox-gl'
import { WARSAW_BOUNDARY } from '@/shared/geo/geo'

// Sources and layers we add on top of the Mapbox Standard style. AED markers themselves are
// HTML (MapView); the clustered `aeds` source only feeds them.

export const EMPTY_COLLECTION: FeatureCollection = { type: 'FeatureCollection', features: [] }

export const SOURCE = {
  aeds: 'aeds',
  route: 'route',
  coverage: 'coverage',
  accuracy: 'origin-accuracy',
  boundary: 'warsaw-boundary',
} as const

export const COVERAGE_LAYER = 'coverage-fill'
export const COVERAGE_HALO_LAYER = 'coverage-halo'
export const ACCURACY_LAYER = 'origin-accuracy'
/** Accuracy area opacity right after a GPS fix; it then fades to 0. */
export const ACCURACY_OPACITY = 0.12
export const AEDS_LAYER = 'aeds-hit'

/** Map colors come from the design tokens (DESIGN.md §2). */
const token = (name: string) => getComputedStyle(document.documentElement).getPropertyValue(name).trim()

/** Translucent fill with diagonal hatching, so gaps never rely on color alone (DESIGN.md §11). */
function hatchPattern(hex: string, size = 12, stripe = 170, base = 45) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
  const data = new Uint8Array(size * size * 4)
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const i = (y * size + x) * 4
      data.set([r, g, b, (x + y) % 6 < 2 ? stripe : base], i)
    }
  }
  return { width: size, height: size, data }
}

export function addAppLayers(map: MapboxMap) {
  const accent = token('--color-accent')
  const surface = token('--color-surface')
  const location = token('--color-location')

  map.addSource(SOURCE.boundary, { type: 'geojson', data: WARSAW_BOUNDARY })
  map.addLayer({
    id: 'warsaw-boundary',
    type: 'line',
    source: SOURCE.boundary,
    slot: 'middle',
    paint: { 'line-color': token('--color-border-control'), 'line-width': 2, 'line-dasharray': [3, 2] },
  })

  // Gaps are red with a strong tint; the white halos of the covered areas are drawn above them.
  map.addImage('hatch-gap', hatchPattern(token('--color-danger'), 12, 215, 95))
  map.addSource(SOURCE.coverage, { type: 'geojson', data: EMPTY_COLLECTION })
  map.addLayer({
    id: COVERAGE_LAYER,
    type: 'fill',
    source: SOURCE.coverage,
    slot: 'middle',
    paint: {
      'fill-pattern': 'hatch-gap',
      'fill-antialias': false,
    },
    filter: ['!=', ['get', 'kind'], 'covered'],
  })
  // White circles around the AEDs that count: soft white fill and a clear outline.
  map.addLayer({
    id: COVERAGE_HALO_LAYER,
    type: 'fill',
    source: SOURCE.coverage,
    slot: 'middle',
    filter: ['==', ['get', 'kind'], 'covered'],
    paint: { 'fill-color': '#ffffff', 'fill-opacity': 0.55, 'fill-outline-color': '#ffffff' },
  })
  map.addLayer({
    id: `${COVERAGE_HALO_LAYER}-edge`,
    type: 'line',
    source: SOURCE.coverage,
    slot: 'middle',
    filter: ['==', ['get', 'kind'], 'covered'],
    paint: { 'line-color': '#ffffff', 'line-width': 3, 'line-opacity': 0.95 },
  })

  map.addSource(SOURCE.accuracy, { type: 'geojson', data: EMPTY_COLLECTION })
  map.addLayer({
    id: ACCURACY_LAYER,
    type: 'fill',
    source: SOURCE.accuracy,
    slot: 'top',
    // Starts hidden; MapView shows it briefly after each fix and lets it fade.
    paint: {
      'fill-color': location,
      'fill-opacity': 0,
      'fill-opacity-transition': { duration: 1200, delay: 0 },
      'fill-outline-color': location,
    },
  })

  // DESIGN.md §7: 5-wide green line over a white casing 9 wide.
  map.addSource(SOURCE.route, { type: 'geojson', data: EMPTY_COLLECTION })
  const lineLayout = { 'line-join': 'round', 'line-cap': 'round' } as const
  map.addLayer({
    id: 'route-casing',
    type: 'line',
    source: SOURCE.route,
    slot: 'top',
    layout: lineLayout,
    paint: { 'line-color': surface, 'line-width': 9 },
  })
  map.addLayer({
    id: 'route-line',
    type: 'line',
    source: SOURCE.route,
    slot: 'top',
    layout: lineLayout,
    paint: { 'line-color': accent, 'line-width': 5 },
  })

  // Single AEDs from zoom 15; a cluster sums `available` (open now) so MapView can tint it.
  map.addSource(SOURCE.aeds, {
    type: 'geojson',
    data: EMPTY_COLLECTION,
    cluster: true,
    clusterRadius: 48,
    clusterMaxZoom: 14,
    clusterProperties: { available: ['+', ['get', 'available']] },
  })
  // Invisible layer that MapView queries to place the HTML markers.
  map.addLayer({
    id: AEDS_LAYER,
    type: 'circle',
    source: SOURCE.aeds,
    paint: { 'circle-radius': 1, 'circle-opacity': 0 },
  })
}

export function setSourceData(map: MapboxMap, id: string, data: GeoJSON) {
  map.getSource<GeoJSONSource>(id)?.setData(data)
}
