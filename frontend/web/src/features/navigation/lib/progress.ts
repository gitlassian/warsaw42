import type { LineString } from 'geojson'
import type { RouteStep } from '../../discovery/models/routing'

type Point = { lng: number; lat: number }

/** Where the walker is: meters walked along the route line and meters away from it. */
export type RouteProgress = { alongM: number; offRouteM: number }

/** Route line measured once, with each step's maneuver placed on it. */
export type RoutePlan = {
  coordinates: [number, number][]
  /** Meters from the start to each coordinate. */
  cumulativeM: number[]
  totalM: number
  /** Meters from the start to each step's maneuver, never decreasing. */
  stepAlongM: number[]
}

/** A maneuver this close behind the walker counts as done, so GPS jitter does not repeat it. */
const PASSED_M = 8
/** The destination counts as reached within this distance. */
export const ARRIVED_M = 20
/** Farther than this from the line (and beyond the GPS accuracy) the walker is off the route. */
export const OFF_ROUTE_M = 40

const M_PER_DEG = 111_320

// Equirectangular meters around `ref`: accurate enough for city-scale walking routes.
function toXY([lng, lat]: [number, number], ref: Point): [number, number] {
  return [(lng - ref.lng) * M_PER_DEG * Math.cos((ref.lat * Math.PI) / 180), (lat - ref.lat) * M_PER_DEG]
}

function segmentLength(a: [number, number], b: [number, number]): number {
  const [x, y] = toXY(b, { lng: a[0], lat: a[1] })
  return Math.hypot(x, y)
}

/** Closest point of segment `i` to `p`: distance to it and meters along the route. */
function project(plan: Pick<RoutePlan, 'coordinates' | 'cumulativeM'>, i: number, p: Point) {
  const a = plan.coordinates[i]
  const b = plan.coordinates[i + 1]
  const [bx, by] = toXY(b, { lng: a[0], lat: a[1] })
  const [px, py] = toXY([p.lng, p.lat], { lng: a[0], lat: a[1] })
  const len2 = bx * bx + by * by
  const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, (px * bx + py * by) / len2))
  const distanceM = Math.hypot(px - t * bx, py - t * by)
  return { distanceM, alongM: plan.cumulativeM[i] + t * (plan.cumulativeM[i + 1] - plan.cumulativeM[i]) }
}

function nearest(plan: Pick<RoutePlan, 'coordinates' | 'cumulativeM'>, p: Point, fromSegment = 0) {
  let best = { distanceM: Infinity, alongM: 0, segment: fromSegment }
  for (let i = fromSegment; i < plan.coordinates.length - 1; i++) {
    const hit = project(plan, i, p)
    if (hit.distanceM < best.distanceM) best = { ...hit, segment: i }
  }
  return best
}

export function planRoute(geometry: LineString, steps: RouteStep[]): RoutePlan {
  const coordinates = geometry.coordinates.map(([lng, lat]) => [lng, lat] as [number, number])
  const cumulativeM = [0]
  for (let i = 1; i < coordinates.length; i++) {
    cumulativeM.push(cumulativeM[i - 1] + segmentLength(coordinates[i - 1], coordinates[i]))
  }
  const totalM = cumulativeM.at(-1) ?? 0
  const base = { coordinates, cumulativeM }
  // Steps come in walking order, so each search starts at the previous step's segment (routes may loop back).
  let segment = 0
  const stepAlongM = steps.map((step) => {
    if (coordinates.length < 2) return 0
    const hit = nearest(base, step.location, segment)
    segment = hit.segment
    return hit.alongM
  })
  return { ...base, totalM, stepAlongM }
}

export function locateOnRoute(plan: RoutePlan, position: Point): RouteProgress {
  if (plan.coordinates.length < 2) return { alongM: 0, offRouteM: Infinity }
  const hit = nearest(plan, position)
  return { alongM: hit.alongM, offRouteM: hit.distanceM }
}

/** Index of the next maneuver ahead of the walker; the last step ("arrive") once all others are done. */
export function upcomingStep(plan: RoutePlan, alongM: number): number {
  const last = plan.stepAlongM.length - 1
  for (let i = 1; i < last; i++) {
    if (plan.stepAlongM[i] > alongM + PASSED_M) return i
  }
  return Math.max(0, last)
}

export function isOffRoute(progress: RouteProgress, accuracyM = 0): boolean {
  return progress.offRouteM > Math.max(OFF_ROUTE_M, accuracyM)
}

export function hasArrived(plan: RoutePlan, progress: RouteProgress): boolean {
  return plan.totalM - progress.alongM <= ARRIVED_M && progress.offRouteM <= OFF_ROUTE_M
}

/** Point `alongM` meters from the start of the route line, clamped to its ends. */
export function pointAlong(plan: RoutePlan, alongM: number): Point {
  const { coordinates: c, cumulativeM: m } = plan
  if (c.length === 0) return { lng: 0, lat: 0 }
  const target = Math.max(0, Math.min(alongM, plan.totalM))
  let i = 0
  while (i < c.length - 2 && m[i + 1] < target) i++
  if (c.length === 1) return { lng: c[0][0], lat: c[0][1] }
  const length = m[i + 1] - m[i]
  const t = length === 0 ? 0 : (target - m[i]) / length
  return { lng: c[i][0] + t * (c[i + 1][0] - c[i][0]), lat: c[i][1] + t * (c[i + 1][1] - c[i][1]) }
}

/** Look-ahead for the heading: smooths small zigzags of the path and GPS noise. */
const HEADING_AHEAD_M = 25

/**
 * Walking direction at `alongM`, in degrees clockwise from north, for a heading-up map.
 * Taken from the route line rather than the GPS heading, which is unreliable at walking speed.
 */
export function headingAt(plan: RoutePlan, alongM: number): number {
  const from = pointAlong(plan, Math.min(alongM, plan.totalM - 1))
  const to = pointAlong(plan, alongM + HEADING_AHEAD_M)
  const [x, y] = toXY([to.lng, to.lat], from)
  if (x === 0 && y === 0) return 0
  return ((Math.atan2(x, y) * 180) / Math.PI + 360) % 360
}
