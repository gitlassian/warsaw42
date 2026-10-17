import type { FeatureCollection, Polygon } from 'geojson'

/** GET /coverage scenarios (ENDPOINTS.md §5). */
export type CoverageScenario = 'all_public' | 'available_at' | 'always_open'

export const COVERAGE_SCENARIOS = [
  { value: 'all_public', label: 'Wszystkie publiczne' },
  { value: 'available_at', label: 'Dostępne o wybranej porze' },
  { value: 'always_open', label: 'Całodobowe' },
] as const satisfies readonly { value: CoverageScenario; label: string }[]

export const COVERAGE_THRESHOLDS = [
  { value: 300, label: '300 m' },
  { value: 500, label: '500 m' },
  { value: 750, label: '750 m' },
  { value: 1000, label: '1 km' },
] as const

export type CoverageCell = {
  /** No eligible AED within the threshold (AEDs without information are not eligible). */
  kind: 'gap'
  nearestDistanceM: number | null
  nearestAedId: string | null
}

export type CoverageLayer = {
  scenario: CoverageScenario
  thresholdM: number
  evaluatedAt: string
  gridSizeM: number
  data: FeatureCollection<Polygon, CoverageCell>
}
