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
}

export type ReportReceipt = { id: string; status: 'pending'; submittedAt: string }

export const DESCRIPTION_MIN = 10
export const DESCRIPTION_MAX = 2000

export type DraftErrors = Partial<Record<keyof ReportDraft, string>>

export function validateDraft(draft: ReportDraft): DraftErrors {
  const errors: DraftErrors = {}
  const length = draft.description.trim().length
  if (!draft.category) errors.category = 'Wybierz rodzaj problemu.'
  if (length < DESCRIPTION_MIN) errors.description = `Opisz problem w co najmniej ${DESCRIPTION_MIN} znakach.`
  if (length > DESCRIPTION_MAX) errors.description = `Opis może mieć najwyżej ${DESCRIPTION_MAX} znaków.`
  return errors
}
