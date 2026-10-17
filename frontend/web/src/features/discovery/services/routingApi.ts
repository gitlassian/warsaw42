import type { LineString } from 'geojson'
import { fetchAeds } from '@/features/aeds/services/aedApi'
import type { LngLat } from '@/shared/geo/geo'
import { callFunction } from '@/shared/lib/supabase'
import type { Eta, FindCandidate, FindResult, RouteStep, WalkingRoute } from '../models/routing'

// Edge Functions aeds-find, routes-etas and routes-walking (ENDPOINTS.md "Finding and routing").
// Their AED view is slim; the full record comes from the cached AED list by id.

type ApiAedRef = { aed: { id: string } }
type ApiWalking = { duration_seconds: number; distance_m: number }
type ApiStep = {
  instruction: string
  maneuver_type: string
  maneuver_modifier: string | null
  street: string | null
  location: [number, number]
  distance_m: number
  duration_seconds: number
}
type ApiRoute = ApiWalking & { geometry: LineString; steps?: ApiStep[] }
type ApiCandidate = ApiAedRef & { walking: ApiWalking | null }

type FindResponse = {
  data: {
    status: FindResult['status']
    selected: (ApiCandidate & { route: ApiRoute | null }) | null
    alternatives: ApiCandidate[]
    unknown_access_alternatives: ApiAedRef[]
  }
  meta: { search: { evaluated_count: number; searched_radius_m: number } }
}
type EtaResponse = { data: (Partial<ApiWalking> & { aed_id: string; status: string })[] }

const ETA_FAILURES = new Set(['no_route', 'not_found', 'provider_error'])

const point = ({ lng, lat }: LngLat) => ({ latitude: lat, longitude: lng })

const toRoute = (aedId: string, r: ApiRoute): WalkingRoute => ({
  aedId,
  durationSeconds: r.duration_seconds,
  distanceM: r.distance_m,
  geometry: r.geometry,
  steps: (r.steps ?? []).map(
    (st): RouteStep => ({
      instruction: st.instruction,
      maneuverType: st.maneuver_type,
      maneuverModifier: st.maneuver_modifier,
      street: st.street,
      location: { lng: st.location[0], lat: st.location[1] },
      distanceM: st.distance_m,
      durationSeconds: st.duration_seconds,
    }),
  ),
})

export async function findAed(origin: LngLat): Promise<FindResult> {
  const [{ data, meta }, aeds] = await Promise.all([
    callFunction<FindResponse>('aeds-find', { origin: point(origin) }),
    fetchAeds(),
  ])
  const byId = new Map(aeds.map((a) => [a.id, a]))
  // Without walking times (routing_unavailable) an AED is not a ranked result.
  const candidate = (c: ApiCandidate): FindCandidate[] => {
    const aed = byId.get(c.aed.id)
    return aed && c.walking ? [{ aed, durationSeconds: c.walking.duration_seconds, distanceM: c.walking.distance_m }] : []
  }
  const [selected = null] = data.selected ? candidate(data.selected) : []
  return {
    status: data.status,
    selected,
    route: selected && data.selected?.route ? toRoute(selected.aed.id, data.selected.route) : null,
    alternatives: data.alternatives.flatMap(candidate),
    unknownAccessAlternatives: data.unknown_access_alternatives.flatMap((u) => byId.get(u.aed.id) ?? []),
    evaluatedCount: meta.search.evaluated_count,
    searchedRadiusM: meta.search.searched_radius_m,
  }
}

export async function fetchEtas(origin: LngLat, aedIds: string[]): Promise<Record<string, Eta>> {
  const { data } = await callFunction<EtaResponse>('routes-etas', { origin: point(origin), aed_ids: aedIds })
  return Object.fromEntries(
    data.map((e): [string, Eta] => [
      e.aed_id,
      e.status === 'ok' && e.duration_seconds !== undefined && e.distance_m !== undefined
        ? { status: 'ok', durationSeconds: e.duration_seconds, distanceM: e.distance_m }
        : { status: ETA_FAILURES.has(e.status) ? (e.status as 'no_route' | 'not_found') : 'provider_error' },
    ]),
  )
}

export async function fetchWalkingRoute(origin: LngLat, aedId: string): Promise<WalkingRoute> {
  const { data } = await callFunction<{ data: ApiRoute }>('routes-walking', { origin: point(origin), aed_id: aedId })
  return toRoute(aedId, data)
}
