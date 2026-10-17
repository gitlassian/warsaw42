import type { Feature, MultiPolygon, Polygon } from 'geojson'
import polygonClipping, { type MultiPolygon as Clip } from 'polygon-clipping'
import type { CoverageCell } from '../models/coverage'

export type Site = { id: string; lng: number; lat: number }

const M_PER_DEG_LAT = 111_320
const CIRCLE_STEPS = 32

function circle({ lng, lat }: Site, radiusM: number): Clip[number] {
  const dLat = radiusM / M_PER_DEG_LAT
  const dLng = dLat / Math.cos((lat * Math.PI) / 180)
  const ring = Array.from({ length: CIRCLE_STEPS }, (_, i) => {
    const angle = (i / CIRCLE_STEPS) * 2 * Math.PI
    return [lng + dLng * Math.cos(angle), lat + dLat * Math.sin(angle)] as [number, number]
  })
  return [[...ring, ring[0]]]
}

const reach = (sites: Site[], radiusM: number): Clip =>
  sites.length ? polygonClipping.union(circle(sites[0], radiusM), ...sites.slice(1).map((s) => circle(s, radiusM))) : []

type Area = Feature<MultiPolygon, Pick<CoverageCell, 'kind'>>

const area = (kind: CoverageCell['kind'], coordinates: Clip): Area[] =>
  coordinates.length ? [{ type: 'Feature', properties: { kind }, geometry: { type: 'MultiPolygon', coordinates } }] : []

/**
 * Where an AED is within reach and where none is. AEDs without information are not eligible (no data means unavailable).
 * - covered: the union of circles of `radiusM` around the eligible AEDs (drawn as white halos)
 * - gap: the rest of the city (drawn red)
 */
export function coverageAreas(boundary: Polygon, eligible: Site[], radiusM: number): Area[] {
  const city = boundary.coordinates as Clip[number]
  const covered = reach(eligible, radiusM)
  const gap = covered.length ? polygonClipping.difference(city, covered) : [city]
  return [...area('gap', gap), ...area('covered', covered)]
}

/** Straight-line distance in meters from a point to the nearest site (equirectangular, fine at city scale). */
export function nearestSite(lng: number, lat: number, sites: Site[]): { site: Site; distanceM: number } | null {
  const mPerDegLng = M_PER_DEG_LAT * Math.cos((lat * Math.PI) / 180)
  let best: { site: Site; distanceM: number } | null = null
  for (const site of sites) {
    const distanceM = Math.hypot((site.lng - lng) * mPerDegLng, (site.lat - lat) * M_PER_DEG_LAT)
    if (!best || distanceM < best.distanceM) best = { site, distanceM }
  }
  return best
}
