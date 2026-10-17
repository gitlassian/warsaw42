import type { Aed } from '@/features/aeds/models/aed'
import { evaluateHours, isOpenThrough } from '@/features/aeds/lib/availability'
import { fetchAeds } from '@/features/aeds/services/aedApi'
import { distanceMeters, type LngLat } from '@/shared/geo/geo'
import { mockLatency } from '@/shared/lib/mockLatency'
import type { Eta, FindCandidate, FindResult, WalkingRoute } from '../models/routing'

// shortcut: mock of POST /aeds/find, /routes/etas and /routes/walking (ENDPOINTS.md §2–3).
// Walking time = straight line × detour at walking pace, geometry is an L-shaped path.
// Replace with the backend (Google Routes) calls; the selection rules below mirror PLAN.md §6.

const WALK_SPEED_MPS = 1.3
const DETOUR_FACTOR = 1.3
const ACCESS_BUFFER_S = 120
const SEARCH_ROUNDS = [
  { radiusM: 2000, limit: 20 },
  { radiusM: 5000, limit: 40 },
]

function mockWalk(origin: LngLat, aed: Aed): FindCandidate {
  const distanceM = Math.round(distanceMeters(origin, aed.location) * DETOUR_FACTOR)
  return { aed, distanceM, durationSeconds: Math.round(distanceM / WALK_SPEED_MPS) }
}

function mockRoute(origin: LngLat, { aed, distanceM, durationSeconds }: FindCandidate): WalkingRoute {
  const { lng, lat } = aed.location
  return {
    aedId: aed.id,
    distanceM,
    durationSeconds,
    geometry: { type: 'LineString', coordinates: [[origin.lng, origin.lat], [origin.lng, lat], [lng, lat]] },
  }
}

export async function findAed(origin: LngLat): Promise<FindResult> {
  const aeds = await fetchAeds()
  await mockLatency(700)
  const now = Date.now()
  const atArrival = (c: FindCandidate, extraS = 0) => new Date(now + (c.durationSeconds + extraS) * 1000)
  const isEligible = (c: FindCandidate) =>
    c.aed.publicAccess === 'public' && isOpenThrough(c.aed.schedule, atArrival(c), atArrival(c, ACCESS_BUFFER_S))
  const byDuration = (a: FindCandidate, b: FindCandidate) => a.durationSeconds - b.durationSeconds || a.distanceM - b.distanceM

  let result: FindResult | null = null
  for (const round of SEARCH_ROUNDS) {
    const candidates = aeds
      .filter((a) => a.operationalStatus !== 'confirmed_unavailable')
      .map((aed) => ({ aed, straightM: distanceMeters(origin, aed.location) }))
      .filter((c) => c.straightM <= round.radiusM)
      .sort((a, b) => a.straightM - b.straightM)
      .slice(0, round.limit)
      .map(({ aed }) => mockWalk(origin, aed))
    const eligible = candidates.filter(isEligible).sort(byDuration)
    const [selected = null, ...alternatives] = eligible
    result = {
      status: selected ? 'found' : 'no_eligible_aed',
      selected,
      route: selected && mockRoute(origin, selected),
      alternatives: alternatives.slice(0, 3),
      unknownAccessAlternatives: candidates
        .filter((c) => !isEligible(c) && (c.aed.publicAccess !== 'public' || evaluateHours(c.aed.schedule, atArrival(c)).state === 'unknown'))
        .sort(byDuration)
        .slice(0, 3),
      evaluatedCount: candidates.length,
      searchedRadiusM: round.radiusM,
    }
    if (selected) break
  }
  return result!
}

export async function fetchEtas(origin: LngLat, aedIds: string[]): Promise<Record<string, Eta>> {
  const aeds = await fetchAeds()
  await mockLatency(500)
  const byId = new Map(aeds.map((a) => [a.id, a]))
  return Object.fromEntries(
    aedIds.map((id) => {
      const aed = byId.get(id)
      if (!aed) return [id, { status: 'not_found' }]
      const { durationSeconds, distanceM } = mockWalk(origin, aed)
      return [id, { status: 'ok', durationSeconds, distanceM }]
    }),
  )
}

export async function fetchWalkingRoute(origin: LngLat, aedId: string): Promise<WalkingRoute> {
  const aed = (await fetchAeds()).find((a) => a.id === aedId)
  await mockLatency(500)
  if (!aed) throw new Error('not_found')
  return mockRoute(origin, mockWalk(origin, aed))
}
