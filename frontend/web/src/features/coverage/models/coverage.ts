import type { FeatureCollection, MultiPolygon } from 'geojson'

/** GET /coverage scenarios (ENDPOINTS.md §5). */
export type CoverageScenario = 'all_public' | 'available_at' | 'always_open'

export const COVERAGE_SCENARIOS = [
  { value: 'all_public', label: 'Wszystkie publiczne' },
  { value: 'available_at', label: 'Dostępne o tej porze' },
  { value: 'always_open', label: 'Całodobowe' },
] as const satisfies readonly { value: CoverageScenario; label: string }[]

/** Reach radius in meters, picked with a slider. */
export const COVERAGE_RADIUS = { min: 100, max: 1000, step: 50 } as const

export type CoverageCell = {
  /** covered: an eligible AED within the threshold; gap: none (AEDs without information are never eligible). */
  kind: 'covered' | 'gap'
  nearestDistanceM: number | null
  nearestAedId: string | null
}

export type CoverageLayer = {
  scenario: CoverageScenario
  thresholdM: number
  evaluatedAt: string
  /** The AEDs behind the white circles, so a tap can name the nearest one. */
  eligible: { id: string; lng: number; lat: number }[]
  data: FeatureCollection<MultiPolygon, Pick<CoverageCell, 'kind'>>
}
