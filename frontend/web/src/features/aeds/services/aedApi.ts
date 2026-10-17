import { mockLatency } from '@/shared/lib/mockLatency'
import { restGet, storagePublicUrl, supabaseEnabled } from '@/shared/lib/supabase'
import { AED_COLUMNS, aedFromRow, type AedRow } from '../lib/fromRow'
import type { Aed, DataStatus } from '../models/aed'
import { t } from '@/i18n'

// With VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY set, AEDs and the data status come from the
// database (`aeds`, `app_data.status`); without them the mock snapshot below is used.

// shortcut: mock of GET /api/v1/aeds and /data/status (ENDPOINTS.md §1, §7) over the
// 17.10.2026 Warsaw snapshot in public/mock/aeds.json, for running without Supabase.

const SNAPSHOT_FETCHED_AT = '2026-10-17T10:00:00+02:00'
const SNAPSHOT_ATTRIBUTION = t('Dane: m.st. Warszawa, SCB (CC BY)')
// Mock-only: exercises the confirmed-unavailable state; the snapshot has no device condition data.
const DEMO_UNAVAILABLE_ID = '663'

let aedsRequest: Promise<Aed[]> | null = null

async function fetchAedsFromDatabase(): Promise<Aed[]> {
  // shortcut: one request; PostgREST caps a response at 1000 rows by default (897 on 17.10.2026), paginate before that.
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

type StatusDocument = { aed_count: number; updated_at: string; attribution: string }

export async function fetchDataStatus(): Promise<DataStatus> {
  if (!supabaseEnabled) {
    const aeds = await fetchAeds()
    return { fetchedAt: SNAPSHOT_FETCHED_AT, aedCount: aeds.length, attribution: SNAPSHOT_ATTRIBUTION }
  }
  const [row] = await restGet<{ data: StatusDocument }[]>('app_data?key=eq.status&select=data')
  if (!row) throw new Error('app_data status missing')
  return { fetchedAt: row.data.updated_at, aedCount: row.data.aed_count, attribution: row.data.attribution }
}
