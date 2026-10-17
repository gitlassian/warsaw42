/** POST /reports categories (ENDPOINTS.md §4) with their interface labels (DESIGN.md §9). */
export const REPORT_CATEGORIES = [
  { value: 'missing', label: 'Brak AED' },
  { value: 'malfunction', label: 'Problem z urządzeniem' },
  { value: 'inaccessible', label: 'Brak dostępu' },
  { value: 'incorrect_hours', label: 'Błędne godziny' },
  { value: 'incorrect_location', label: 'Błędna lokalizacja' },
  { value: 'other', label: 'Inny problem' },
] as const

export type ReportCategory = (typeof REPORT_CATEGORIES)[number]['value']

export type ReportDraft = {
  category: ReportCategory | null
  description: string
  phone: string
}

/** Returned by POST /reports/otp/request|resend. Times are epoch ms. */
export type OtpChallenge = {
  challengeId: string
  maskedPhone: string
  codeLength: number
  expiresAt: number
  resendAt: number
}

export type ReportReceipt = { id: string; status: 'pending'; submittedAt: string }

export const DESCRIPTION_MIN = 10
export const DESCRIPTION_MAX = 2000

/** Polish mobile number in E.164 ("+48…"), or null. Accepts spaces, dashes and an optional +48/0048. */
export function toE164(phone: string): string | null {
  const digits = phone.replace(/[\s-]/g, '').replace(/^(\+48|0048)/, '')
  return /^\d{9}$/.test(digits) ? `+48${digits}` : null
}

export type DraftErrors = Partial<Record<keyof ReportDraft, string>>

export function validateDraft(draft: ReportDraft): DraftErrors {
  const errors: DraftErrors = {}
  const length = draft.description.trim().length
  if (!draft.category) errors.category = 'Wybierz rodzaj problemu.'
  if (length < DESCRIPTION_MIN) errors.description = `Opisz problem w co najmniej ${DESCRIPTION_MIN} znakach.`
  if (length > DESCRIPTION_MAX) errors.description = `Opis może mieć najwyżej ${DESCRIPTION_MAX} znaków.`
  if (!toE164(draft.phone)) errors.phone = 'Wpisz 9-cyfrowy numer telefonu, np. 600 123 456.'
  return errors
}
