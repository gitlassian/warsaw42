import type { Feature, Polygon } from 'geojson'
import { evaluateHours } from '@/features/aeds/lib/availability'
import type { Aed } from '@/features/aeds/models/aed'
import { fetchAeds } from '@/features/aeds/services/aedApi'
import { WARSAW_BOUNDARY, isInsideWarsaw } from '@/shared/geo/geo'
import { mockLatency } from '@/shared/lib/mockLatency'
import type { CoverageCell, CoverageLayer, CoverageScenario } from '../models/coverage'

// shortcut: client-side mock of GET /coverage (ENDPOINTS.md §5, PLAN.md §9): straight-line distance
// from 250 m cell centers, cells are not merged into regions. Replace with the precomputed backend layer.

const GRID_SIZE_M = 250
const M_PER_DEG_LAT = 111_320

type Query = { scenario: CoverageScenario; thresholdM: number; at: Date }

export async function fetchCoverage({ scenario, thresholdM, at }: Query): Promise<CoverageLayer> {
  const aeds = await fetchAeds()
  await mockLatency(400)

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

  const lngs = WARSAW_BOUNDARY.coordinates[0].map(([lng]) => lng)
  const lats = WARSAW_BOUNDARY.coordinates[0].map(([, lat]) => lat)
  const [west, east, south, north] = [Math.min(...lngs), Math.max(...lngs), Math.min(...lats), Math.max(...lats)]
  const mPerDegLng = M_PER_DEG_LAT * Math.cos((((south + north) / 2) * Math.PI) / 180)
  const dLat = GRID_SIZE_M / M_PER_DEG_LAT
  const dLng = GRID_SIZE_M / mPerDegLng

  // Equirectangular distance is accurate enough at city scale.
  const nearest = (lng: number, lat: number, list: Aed[]) => {
    let best: { d: number; id: string | null } = { d: Infinity, id: null }
    for (const a of list) {
      const d = Math.hypot((a.location.lng - lng) * mPerDegLng, (a.location.lat - lat) * M_PER_DEG_LAT)
      if (d < best.d) best = { d, id: a.id }
    }
    return best
  }

  const features: Feature<Polygon, CoverageCell>[] = []
  for (let lat = south + dLat / 2; lat < north; lat += dLat) {
    for (let lng = west + dLng / 2; lng < east; lng += dLng) {
      if (!isInsideWarsaw({ lng, lat })) continue
      const near = nearest(lng, lat, eligible)
      if (near.d <= thresholdM) continue
      const covered = unknownHours.length > 0 && nearest(lng, lat, unknownHours).d <= thresholdM
      const [w, e, s, n] = [lng - dLng / 2, lng + dLng / 2, lat - dLat / 2, lat + dLat / 2]
      features.push({
        type: 'Feature',
        geometry: { type: 'Polygon', coordinates: [[[w, s], [e, s], [e, n], [w, n], [w, s]]] },
        properties: {
          kind: covered ? 'uncertain' : 'gap',
          nearestDistanceM: near.id ? Math.round(near.d) : null,
          nearestAedId: near.id,
        },
      })
    }
  }

  return {
    scenario,
    thresholdM,
    evaluatedAt: at.toISOString(),
    gridSizeM: GRID_SIZE_M,
    data: { type: 'FeatureCollection', features },
  }
}
