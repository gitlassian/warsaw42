import { ApiError } from '@/shared/lib/apiError'
import { mockLatency } from '@/shared/lib/mockLatency'
import { restInsert, supabaseEnabled } from '@/shared/lib/supabase'
import type { ReportDraft, ReportReceipt } from '../models/report'

// POST /reports (ENDPOINTS.md §4): a direct PostgREST insert with the publishable key.
// The idempotency key is the report id, so a retry of a stored report fails with 409 and counts as sent.

export async function submitReport(
  aedId: string,
  draft: ReportDraft,
  idempotencyKey: string,
  formMs: number,
): Promise<ReportReceipt> {
  const receipt: ReportReceipt = { id: idempotencyKey, status: 'pending', submittedAt: new Date().toISOString() }
  // shortcut: on the mock AED snapshot (no Supabase settings) ids are not database ids; only simulate.
  if (!supabaseEnabled) {
    await mockLatency(500)
    return receipt
  }
  try {
    await restInsert('reports', {
      id: idempotencyKey,
      aed_id: aedId,
      category: draft.category,
      description: draft.description.trim(),
      form_ms: Math.round(formMs),
    })
  } catch (e) {
    if (!(e instanceof ApiError && e.code === 'http_409')) throw e
  }
  return receipt
}
