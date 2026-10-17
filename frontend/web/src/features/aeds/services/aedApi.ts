import { mockLatency } from '@/shared/lib/mockLatency'
import type { Aed, DataStatus } from '../models/aed'

// shortcut: mock of GET /api/v1/aeds and /data/status (ENDPOINTS.md §1, §7) over the
// 17.10.2026 Warsaw snapshot in public/mock/aeds.json; replace with the HTTP client when the API is deployed.

const SNAPSHOT_FETCHED_AT = '2026-10-17T10:00:00+02:00'
const REFRESH_INTERVAL_MS = 2 * 60 * 60 * 1000
// Mock-only: exercises the confirmed-unavailable state; the snapshot has no device condition data.
const DEMO_UNAVAILABLE_ID = '663'

let aedsRequest: Promise<Aed[]> | null = null

export function fetchAeds(): Promise<Aed[]> {
  aedsRequest ??= fetch('/mock/aeds.json')
    .then((response) => {
      if (!response.ok) throw new Error(`aeds ${response.status}`)
      return response.json() as Promise<Aed[]>
    })
    .then(async (aeds) => {
      await mockLatency()
      return aeds.map((a) => (a.id === DEMO_UNAVAILABLE_ID ? { ...a, operationalStatus: 'confirmed_unavailable' as const } : a))
    })
    .catch((error: unknown) => {
      aedsRequest = null
      throw error
    })
  return aedsRequest
}

export async function fetchDataStatus(): Promise<DataStatus> {
  const aeds = await fetchAeds()
  // The backend flags a missed sync after two expected intervals (PLAN.md §4).
  const stale = Date.now() - Date.parse(SNAPSHOT_FETCHED_AT) > 2 * REFRESH_INTERVAL_MS
  return {
    datasetVersion: '2026-10-17',
    fetchedAt: SNAPSHOT_FETCHED_AT,
    sync: stale ? 'stale' : 'fresh',
    aedCount: aeds.length,
    source: 'Stołeczne Centrum Bezpieczeństwa, dane.um.warszawa.pl',
    license: 'CC BY',
  }
}
