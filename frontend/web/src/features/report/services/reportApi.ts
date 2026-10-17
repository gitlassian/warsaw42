import { ApiError } from '@/shared/lib/apiError'
import { mockLatency } from '@/shared/lib/mockLatency'
import type { OtpChallenge, ReportDraft, ReportReceipt } from '../models/report'

// shortcut: mock of POST /reports/otp/request|resend|verify and POST /reports (ENDPOINTS.md §4).
// Code 123456 always verifies; replace with the Supabase Phone Auth (Twilio) endpoints.

export const MOCK_OTP_CODE = '123456'

const OTP_LIFETIME_MS = 5 * 60_000
const RESEND_COOLDOWN_MS = 60_000

const challenges = new Map<string, OtpChallenge>()

function issueChallenge(challengeId: string, maskedPhone: string): OtpChallenge {
  const now = Date.now()
  const challenge = {
    challengeId,
    maskedPhone,
    codeLength: MOCK_OTP_CODE.length,
    expiresAt: now + OTP_LIFETIME_MS,
    resendAt: now + RESEND_COOLDOWN_MS,
  }
  challenges.set(challengeId, challenge)
  return challenge
}

/** Binds a new challenge to the validated draft. `phone` is E.164. */
export async function requestOtp(_aedId: string, _draft: ReportDraft, phone: string): Promise<OtpChallenge> {
  await mockLatency(600)
  return issueChallenge(crypto.randomUUID(), `${phone.slice(0, 3)} ••• ••• ${phone.slice(-3)}`)
}

export async function resendOtp(challengeId: string): Promise<OtpChallenge> {
  await mockLatency(400)
  const challenge = challenges.get(challengeId)
  if (!challenge) throw new ApiError('challenge_not_found')
  if (Date.now() < challenge.resendAt) throw new ApiError('rate_limited', challenge.resendAt)
  return issueChallenge(challengeId, challenge.maskedPhone)
}

/** Returns a single-use report token bound to the draft. */
export async function verifyOtp(challengeId: string, code: string): Promise<string> {
  await mockLatency(500)
  const challenge = challenges.get(challengeId)
  if (!challenge || Date.now() > challenge.expiresAt) throw new ApiError('otp_expired')
  if (code !== MOCK_OTP_CODE) throw new ApiError('otp_invalid')
  challenges.delete(challengeId)
  return `mock-report-token-${challengeId}`
}

export async function submitReport(_reportToken: string, _idempotencyKey: string): Promise<ReportReceipt> {
  await mockLatency(500)
  return { id: crypto.randomUUID(), status: 'pending', submittedAt: new Date().toISOString() }
}
