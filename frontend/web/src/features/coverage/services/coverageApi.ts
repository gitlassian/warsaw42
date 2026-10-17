import { evaluateHours } from '@/features/aeds/lib/availability'
import { fetchAeds } from '@/features/aeds/services/aedApi'
import { WARSAW_BOUNDARY } from '@/shared/geo/geo'
import { mockLatency } from '@/shared/lib/mockLatency'
import { coverageAreas, type Site } from '../lib/coverageGeometry'
import type { CoverageLayer, CoverageScenario } from '../models/coverage'

// shortcut: client-side mock of GET /coverage (ENDPOINTS.md §5, PLAN.md §9): circles of the threshold radius
// (straight line) around the eligible AEDs, merged into regions. Replace with the precomputed backend layer.

type Query = { scenario: CoverageScenario; thresholdM: number; at: Date }

export async function fetchCoverage({ scenario, thresholdM, at }: Query): Promise<CoverageLayer> {
  const aeds = await fetchAeds()
  await mockLatency(200)

  // Every scenario excludes confirmed unavailable and non-public devices.
  const usable = aeds.filter((a) => a.publicAccess === 'public' && a.operationalStatus !== 'confirmed_unavailable')
  const eligible = usable.filter((a) =>
    scenario === 'all_public'
      ? true
      : scenario === 'always_open'
        ? a.schedule.kind === 'always_open'
        : evaluateHours(a.schedule, at).state === 'open',
  )
  const unknownHours =
    scenario === 'available_at' ? usable.filter((a) => evaluateHours(a.schedule, at).state === 'unknown') : []
  const site = (a: (typeof aeds)[number]): Site => ({ id: a.id, lng: a.location.lng, lat: a.location.lat })
  const sites = eligible.map(site)

  return {
    scenario,
    thresholdM,
    evaluatedAt: at.toISOString(),
    eligible: sites,
    data: { type: 'FeatureCollection', features: coverageAreas(WARSAW_BOUNDARY, sites, unknownHours.map(site), thresholdM) },
  }
}
