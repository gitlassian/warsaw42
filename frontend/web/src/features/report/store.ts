import { ApiError } from '@/shared/lib/apiError'
import { createStore } from '@/shared/lib/store'
import type { ReportDraft, ReportReceipt } from './models/report'
import { submitReport } from './services/reportApi'

export type ReportStep = 'form' | 'done'

/** Per-AED report flow. Kept in memory only: the draft survives errors and back navigation. */
export type ReportFlow = {
  draft: ReportDraft
  step: ReportStep
  busy: boolean
  /** Stable error code, localized by the panel. */
  error: string | null
  receipt: ReportReceipt | null
  /** One key per draft, so a retried submission cannot create a duplicate. */
  idempotencyKey: string
  /** When the form was first opened; the elapsed time is sent as a spam signal. */
  openedAt: number
}

const emptyFlow = (): ReportFlow => ({
  draft: { category: null, description: '' },
  step: 'form',
  busy: false,
  error: null,
  receipt: null,
  idempotencyKey: crypto.randomUUID(),
  openedAt: Date.now(),
})

export const reportStore = createStore<{ flows: Record<string, ReportFlow> }>({ flows: {} })

export const getFlow = (aedId: string) => reportStore.get().flows[aedId] ?? emptyFlow()

function update(aedId: string, patch: Partial<ReportFlow>) {
  reportStore.set((s) => ({ flows: { ...s.flows, [aedId]: { ...getFlow(aedId), ...patch } } }))
}

/** Starts timing the form; keeps an existing draft. */
export function openFlow(aedId: string) {
  if (!reportStore.get().flows[aedId]) update(aedId, {})
}

const errorCode = (e: unknown) => (e instanceof ApiError ? e.code : 'network')

export function updateDraft(aedId: string, patch: Partial<ReportDraft>) {
  update(aedId, { draft: { ...getFlow(aedId).draft, ...patch }, error: null })
}

/**
 * "Wyślij zgłoszenie". The caller validates the draft first.
 * A filled honeypot means a form-filling bot: show success without sending anything.
 */
export async function submit(aedId: string, honeypot = '') {
  const { draft, idempotencyKey, openedAt } = getFlow(aedId)
  if (honeypot) {
    update(aedId, { step: 'done', receipt: { id: idempotencyKey, status: 'pending', submittedAt: new Date().toISOString() } })
    return
  }
  update(aedId, { busy: true, error: null })
  try {
    const receipt = await submitReport(aedId, draft, idempotencyKey, Date.now() - openedAt)
    update(aedId, { busy: false, step: 'done', receipt })
  } catch (e) {
    update(aedId, { busy: false, error: errorCode(e) })
  }
}

export function resetFlow(aedId: string) {
  reportStore.set((s) => {
    const flows = { ...s.flows }
    delete flows[aedId]
    return { flows }
  })
}
