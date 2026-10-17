import type { LineString } from 'geojson'
import type { Aed } from '@/features/aeds/models/aed'
import type { LngLat } from '@/shared/geo/geo'

/** Search start: GPS position or a point the user picked on the map (never a silent demo location). */
export type Origin = LngLat & { source: 'gps' | 'manual'; accuracyM?: number }

export type LocationIssue =
  | 'denied' // permission refused
  | 'unavailable' // positioning failed
  | 'outside' // GPS position outside Warsaw
  | 'outside_pick' // picked point outside Warsaw

/** POST /routes/etas element (ENDPOINTS.md §3). Failed entries carry no numbers. */
export type Eta =
  | { status: 'ok'; durationSeconds: number; distanceM: number }
  | { status: 'no_route' | 'not_found' | 'provider_error' }

/** Map/list state of one ETA: pending request or a result. */
export type EtaEntry = Eta | 'loading'

export type WalkingRoute = {
  aedId: string
  durationSeconds: number
  distanceM: number
  geometry: LineString
}

export type FindCandidate = {
  aed: Aed
  durationSeconds: number
  distanceM: number
}

/** POST /aeds/find (ENDPOINTS.md §2). Ranking applies to evaluated candidates only. */
export type FindResult = {
  status: 'found' | 'no_eligible_aed' | 'routing_unavailable'
  selected: FindCandidate | null
  route: WalkingRoute | null
  alternatives: FindCandidate[]
  /** Unknown hours or restricted access; never treated as eligible and carry no walking time. */
  unknownAccessAlternatives: Aed[]
  evaluatedCount: number
  searchedRadiusM: number
}
