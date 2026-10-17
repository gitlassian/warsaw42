import { aedsStore } from '@/features/aeds/store'
import { distanceMeters, isInsideWarsaw, type LngLat } from '@/shared/geo/geo'
import { createStore } from '@/shared/lib/store'
import type { EtaEntry, FindResult, LocationIssue, Origin, WalkingRoute } from './models/routing'
import { getCurrentPosition } from './services/geolocation'
import { fetchEtas, fetchWalkingRoute, findAed } from './services/routingApi'

/** Pills are computed only for nearby markers, in bounded batches (PLAN.md §3). */
const ETA_RADIUS_M = 2000
const ETA_BATCH_SIZE = 20

type SearchState =
  | { status: 'idle' }
  | { status: 'searching' }
  | { status: 'done'; result: FindResult }
  | { status: 'failed' }

type DiscoveryState = {
  origin: Origin | null
  locating: boolean
  issue: LocationIssue | null
  /** Waiting for the user to tap a start point on the map. */
  picking: boolean
  search: SearchState
  etas: Record<string, EtaEntry>
  route: WalkingRoute | null
  routing: { aedId: string; status: 'loading' | 'failed' } | null
}

export const discoveryStore = createStore<DiscoveryState>({
  origin: null,
  locating: false,
  issue: null,
  picking: false,
  search: { status: 'idle' },
  etas: {},
  route: null,
  routing: null,
})

// Bumped on every new search or cancel so stale responses are dropped.
let searchToken = 0
let onPicked: ((origin: Origin) => void) | null = null

function setOrigin(origin: Origin) {
  discoveryStore.set((s) => ({
    origin,
    issue: null,
    etas: {},
    route: null,
    routing: null,
    search: s.search.status === 'searching' ? s.search : { status: 'idle' },
  }))
}

/** GPS fix inside Warsaw, or null with `issue` set. A position outside the city is reported, never clamped. */
export async function locate(): Promise<Origin | null> {
  discoveryStore.set({ locating: true, issue: null })
  const position = await getCurrentPosition()
  discoveryStore.set({ locating: false })
  if (typeof position === 'string') {
    discoveryStore.set({ issue: position })
    return null
  }
  if (!isInsideWarsaw(position)) {
    discoveryStore.set({ issue: 'outside' })
    return null
  }
  setOrigin(position)
  return position
}

async function runFind(origin: Origin, token: number): Promise<FindResult | null> {
  try {
    const result = await findAed(origin)
    if (token !== searchToken) return null
    const found = [result.selected, ...result.alternatives].flatMap((c) =>
      c ? [[c.aed.id, { status: 'ok' as const, durationSeconds: c.durationSeconds, distanceM: c.distanceM }]] : [],
    )
    discoveryStore.set((s) => ({
      search: { status: 'done', result },
      route: result.route,
      routing: null,
      etas: { ...s.etas, ...Object.fromEntries(found) },
    }))
    return result
  } catch {
    if (token === searchToken) discoveryStore.set({ search: { status: 'failed' } })
    return null
  }
}

/** "Znajdź defibrylator": a picked start point if there is one, otherwise a fresh GPS fix. */
export async function findNearest(): Promise<FindResult | null> {
  const token = ++searchToken
  discoveryStore.set({ search: { status: 'searching' } })
  const { origin } = discoveryStore.get()
  const start = origin?.source === 'manual' ? origin : await locate()
  if (token !== searchToken) return null
  if (!start) {
    discoveryStore.set({ search: { status: 'idle' } })
    return null
  }
  return runFind(start, token)
}

export function findFrom(origin: Origin): Promise<FindResult | null> {
  const token = ++searchToken
  discoveryStore.set({ search: { status: 'searching' } })
  return runFind(origin, token)
}

/** Closing the selected AED also removes its walking route from the map. */
export function clearRoute() {
  discoveryStore.set({ route: null, routing: null })
}

export function cancelSearch() {
  searchToken++
  discoveryStore.set({ search: { status: 'idle' } })
}

/** Starts manual origin selection; `then` runs once a valid point is picked. */
export function startPicking(then?: (origin: Origin) => void) {
  onPicked = then ?? null
  discoveryStore.set({ picking: true, issue: null })
}

export function stopPicking() {
  onPicked = null
  discoveryStore.set((s) => ({ picking: false, issue: s.issue === 'outside_pick' ? null : s.issue }))
}

export function pickOrigin({ lng, lat }: LngLat) {
  if (!isInsideWarsaw({ lng, lat })) {
    discoveryStore.set({ issue: 'outside_pick' })
    return
  }
  const origin: Origin = { lng, lat, source: 'manual' }
  const then = onPicked
  stopPicking()
  setOrigin(origin)
  then?.(origin)
}

/** Requests walking times for the nearest of `aedIds` that have none yet. */
export async function requestEtas(aedIds: string[]) {
  const { origin, etas } = discoveryStore.get()
  if (!origin) return
  const { byId } = aedsStore.get()
  const ids = aedIds
    .filter((id) => !(id in etas))
    .flatMap((id) => {
      const aed = byId.get(id)
      const distance = aed ? distanceMeters(origin, aed.location) : Infinity
      return distance <= ETA_RADIUS_M ? [{ id, distance }] : []
    })
    .sort((a, b) => a.distance - b.distance)
    .slice(0, ETA_BATCH_SIZE)
    .map((c) => c.id)
  if (!ids.length) return

  const mark = (entry: (id: string) => EtaEntry) =>
    discoveryStore.set((s) => ({ etas: { ...s.etas, ...Object.fromEntries(ids.map((id) => [id, entry(id)])) } }))
  mark(() => 'loading')
  try {
    const result = await fetchEtas(origin, ids)
    if (discoveryStore.get().origin === origin) mark((id) => result[id] ?? { status: 'provider_error' })
  } catch {
    if (discoveryStore.get().origin === origin) mark(() => ({ status: 'provider_error' }))
  }
}

/** "Wyznacz trasę" for a manually selected AED. */
export async function routeTo(aedId: string) {
  discoveryStore.set({ routing: { aedId, status: 'loading' } })
  const origin = discoveryStore.get().origin ?? (await locate())
  // A fresh GPS origin resets `routing`, so mark the request again.
  discoveryStore.set({ routing: origin ? { aedId, status: 'loading' } : null })
  if (!origin) return
  try {
    const route = await fetchWalkingRoute(origin, aedId)
    if (discoveryStore.get().origin !== origin) return
    discoveryStore.set((s) => ({
      route,
      routing: null,
      etas: { ...s.etas, [aedId]: { status: 'ok', durationSeconds: route.durationSeconds, distanceM: route.distanceM } },
    }))
  } catch {
    discoveryStore.set({ routing: { aedId, status: 'failed' } })
  }
}

/** New route from the walker's live position, after navigation went off the route. */
export function rerouteFrom(origin: Origin, aedId: string) {
  if (!isInsideWarsaw(origin)) {
    discoveryStore.set({ issue: 'outside' })
    return
  }
  setOrigin(origin)
  return routeTo(aedId)
}
