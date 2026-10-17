import { mockLatency } from '@/shared/lib/mockLatency'
import { restGet, storagePublicUrl, supabaseEnabled } from '@/shared/lib/supabase'
import { AED_COLUMNS, aedFromRow, type AedRow } from '../lib/fromRow'
import type { Aed, DataStatus } from '../models/aed'

// With VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY set, AEDs and the data status come from the
// database (`aeds`, `app_data.status`); without them the mock snapshot below is used.

// shortcut: mock of GET /api/v1/aeds and /data/status (ENDPOINTS.md §1, §7) over the
// 17.10.2026 Warsaw snapshot in public/mock/aeds.json; replace with the HTTP client when the API is deployed.

const SNAPSHOT_FETCHED_AT = '2026-10-17T10:00:00+02:00'
const REFRESH_INTERVAL_MS = 2 * 60 * 60 * 1000
// Mock-only: exercises the confirmed-unavailable state; the snapshot has no device condition data.
const DEMO_UNAVAILABLE_ID = '663'

let aedsRequest: Promise<Aed[]> | null = null

async function fetchAedsFromDatabase(): Promise<Aed[]> {
  const rows = await restGet<AedRow[]>(`aeds?active=eq.true&select=${AED_COLUMNS}&order=source_id`)
  return rows.map((row) => aedFromRow(row, (file) => storagePublicUrl('aed-photos', file)))
}

export function fetchAeds(): Promise<Aed[]> {
  aedsRequest ??= (supabaseEnabled ? fetchAedsFromDatabase() : fetchMockAeds())
    .catch((error: unknown) => {
      aedsRequest = null
      throw error
    })
  return aedsRequest
}

function fetchMockAeds(): Promise<Aed[]> {
  return fetch('/mock/aeds.json')
    .then((response) => {
      if (!response.ok) throw new Error(`aeds ${response.status}`)
      return response.json() as Promise<Aed[]>
    })
    .then(async (aeds) => {
      await mockLatency()
      return aeds.map((a) => (a.id === DEMO_UNAVAILABLE_ID ? { ...a, operationalStatus: 'confirmed_unavailable' as const } : a))
    })
}

type StatusDocument = { aed_count: number; source: string; updated_at: string }

async function fetchDatabaseStatus(): Promise<DataStatus> {
  const [row] = await restGet<{ data: StatusDocument }[]>('app_data?key=eq.status&select=data')
  if (!row) throw new Error('app_data status missing')
  const { aed_count, source, updated_at } = row.data
  return {
    datasetVersion: updated_at.slice(0, 10),
    fetchedAt: updated_at,
    sync: Date.now() - Date.parse(updated_at) > 2 * REFRESH_INTERVAL_MS ? 'stale' : 'fresh',
    aedCount: aed_count,
    source: `${source} (dane.um.warszawa.pl)`,
    license: 'CC BY',
  }
}

export async function fetchDataStatus(): Promise<DataStatus> {
  if (supabaseEnabled) return fetchDatabaseStatus()
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
