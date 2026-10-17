import type { Polygon } from 'geojson'
import boundary from './warsawBoundary.json'

export type LngLat = { lng: number; lat: number }

/** Warsaw administrative boundary: OSM relation 336075, simplified. © OpenStreetMap contributors (ODbL). */
export const WARSAW_BOUNDARY = boundary as Polygon

const ring = WARSAW_BOUNDARY.coordinates[0]

export const WARSAW_CENTER: LngLat = { lng: 21.0122, lat: 52.2297 }

/** Camera limit: the city bbox with a small margin (PLAN.md §1). */
export const WARSAW_MAX_BOUNDS: [[number, number], [number, number]] = [
  [20.72, 52.02],
  [21.4, 52.44],
]

/** Ray casting against the city boundary; origins outside are rejected, never clamped. */
export function isInsideWarsaw({ lng, lat }: LngLat): boolean {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i]
    const [xj, yj] = ring[j]
    if (yi > lat !== yj > lat && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside
  }
  return inside
}

const EARTH_RADIUS_M = 6_371_000
const toRad = (deg: number) => (deg * Math.PI) / 180

/** Great-circle distance in meters. */
export function distanceMeters(a: LngLat, b: LngLat): number {
  const dLat = toRad(b.lat - a.lat)
  const dLng = toRad(b.lng - a.lng)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h))
}

/** Polygon approximating a circle, for the GPS accuracy area. */
export function circlePolygon(center: LngLat, radiusM: number, steps = 48): Polygon {
  const dLat = radiusM / 111_320
  const dLng = dLat / Math.cos(toRad(center.lat))
  const ring = Array.from({ length: steps + 1 }, (_, i) => {
    const angle = (i / steps) * 2 * Math.PI
    return [center.lng + dLng * Math.cos(angle), center.lat + dLat * Math.sin(angle)]
  })
  return { type: 'Polygon', coordinates: [ring] }
}
