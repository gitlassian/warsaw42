import { ApiError } from '@/shared/lib/apiError'
import { createStore } from '@/shared/lib/store'
import { toE164, type OtpChallenge, type ReportDraft, type ReportReceipt } from './models/report'
import { requestOtp, resendOtp, submitReport, verifyOtp } from './services/reportApi'

export type ReportStep = 'form' | 'verify' | 'done'

/** Per-AED report flow. Kept in memory only: the draft survives errors and back navigation, the phone never persists. */
export type ReportFlow = {
  draft: ReportDraft
  step: ReportStep
  challenge: OtpChallenge | null
  busy: boolean
  /** Stable error code, localized by the panel. */
  error: string | null
  retryAt: number | null
  receipt: ReportReceipt | null
  /** Kept after verification so a failed submission retries without a new code. */
  reportToken: string | null
  /** One key per verified draft, so a retried submission cannot create a duplicate. */
  idempotencyKey: string
}

const emptyFlow = (): ReportFlow => ({
  draft: { category: null, description: '', phone: '' },
  step: 'form',
  challenge: null,
  busy: false,
  error: null,
  retryAt: null,
  receipt: null,
  reportToken: null,
  idempotencyKey: crypto.randomUUID(),
})

export const reportStore = createStore<{ flows: Record<string, ReportFlow> }>({ flows: {} })

export const getFlow = (aedId: string) => reportStore.get().flows[aedId] ?? emptyFlow()

function update(aedId: string, patch: Partial<ReportFlow>) {
  reportStore.set((s) => ({ flows: { ...s.flows, [aedId]: { ...getFlow(aedId), ...patch } } }))
}

const errorCode = (e: unknown) => (e instanceof ApiError ? e.code : 'network')

export function updateDraft(aedId: string, patch: Partial<ReportDraft>) {
  update(aedId, { draft: { ...getFlow(aedId).draft, ...patch }, error: null })
}

/** "Wyślij kod SMS". The caller validates the draft first. */
export async function sendCode(aedId: string) {
  const { draft } = getFlow(aedId)
  update(aedId, { busy: true, error: null })
  try {
    const challenge = await requestOtp(aedId, draft, toE164(draft.phone)!)
    update(aedId, { busy: false, challenge, step: 'verify' })
  } catch (e) {
    update(aedId, { busy: false, error: errorCode(e) })
  }
}

export async function resendCode(aedId: string) {
  const { challenge } = getFlow(aedId)
  if (!challenge) return
  update(aedId, { busy: true, error: null })
  try {
    update(aedId, { busy: false, challenge: await resendOtp(challenge.challengeId) })
  } catch (e) {
    update(aedId, { busy: false, error: errorCode(e), retryAt: e instanceof ApiError ? (e.retryAt ?? null) : null })
  }
}

/** "Potwierdź i wyślij": verifies the code, then submits with the single-use token. */
export async function confirmAndSubmit(aedId: string, code: string) {
  const { challenge, idempotencyKey, reportToken } = getFlow(aedId)
  if (!challenge) return
  update(aedId, { busy: true, error: null })
  try {
    const token = reportToken ?? (await verifyOtp(challenge.challengeId, code.trim()))
    update(aedId, { reportToken: token })
    const receipt = await submitReport(token, idempotencyKey)
    update(aedId, { busy: false, step: 'done', receipt, challenge: null, reportToken: null })
  } catch (e) {
    update(aedId, { busy: false, error: errorCode(e) })
  }
}

/** Back to the form to correct the phone or text; a new challenge is required afterwards. */
export function editDraft(aedId: string) {
  update(aedId, { step: 'form', challenge: null, reportToken: null, error: null })
}

export function resetFlow(aedId: string) {
  reportStore.set((s) => {
    const flows = { ...s.flows }
    delete flows[aedId]
    return { flows }
  })
}
