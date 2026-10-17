import { ApiError } from '@/shared/lib/apiError'
import { mockLatency } from '@/shared/lib/mockLatency'
import type { ReportDraft, ReportReceipt } from '../models/report'

// POST /reports (ENDPOINTS.md §4): a direct PostgREST insert with the publishable key.
// The idempotency key is the report id, so a retry of a stored report fails with 409 and counts as sent.

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL as string | undefined
const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined

async function request(path: string, init: RequestInit = {}, extraHeaders: Record<string, string> = {}): Promise<Response> {
  const headers = { apikey: SUPABASE_KEY!, 'Content-Type': 'application/json', ...extraHeaders }
  try {
    return await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { ...init, headers })
  } catch {
    throw new ApiError('network')
  }
}

// shortcut: app AED ids are city source ids from the mock snapshot (aedApi.ts), while reports
// reference the database uuid. Drop this lookup once the AED API returns database ids.
const aedUuids = new Map<string, string>()

async function aedUuid(sourceId: string): Promise<string> {
  const cached = aedUuids.get(sourceId)
  if (cached) return cached
  const response = await request(`aeds?select=id&active=is.true&source_id=eq.${encodeURIComponent(sourceId)}`)
  if (!response.ok) throw new ApiError(`http_${response.status}`)
  const [row] = (await response.json()) as { id: string }[]
  if (!row) throw new ApiError('aed_not_found')
  aedUuids.set(sourceId, row.id)
  return row.id
}

export async function submitReport(
  aedId: string,
  draft: ReportDraft,
  idempotencyKey: string,
  formMs: number,
): Promise<ReportReceipt> {
  const receipt: ReportReceipt = { id: idempotencyKey, status: 'pending', submittedAt: new Date().toISOString() }
  // shortcut: without Supabase settings (.env.local) the submission is only simulated.
  if (!SUPABASE_URL || !SUPABASE_KEY) {
    await mockLatency(500)
    return receipt
  }
  const body = {
    id: idempotencyKey,
    aed_id: await aedUuid(aedId),
    category: draft.category,
    description: draft.description.trim(),
    form_ms: Math.round(formMs),
  }
  // return=minimal: anon cannot read reports back, so asking for the row would fail RLS.
  const response = await request('reports', { method: 'POST', body: JSON.stringify(body) }, { Prefer: 'return=minimal' })
  if (response.ok || response.status === 409) return receipt
  if (response.status === 429) throw new ApiError('rate_limited')
  throw new ApiError(`http_${response.status}`)
}
