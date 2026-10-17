import { t } from '../../../i18n/index.ts'

/** POST /reports categories (ENDPOINTS.md §4) with their interface labels (DESIGN.md §9). */
export const REPORT_CATEGORIES = [
  { value: 'missing', label: t('Brak AED') },
  { value: 'malfunction', label: t('Problem z urządzeniem') },
  { value: 'inaccessible', label: t('Brak dostępu') },
  { value: 'incorrect_hours', label: t('Błędne godziny') },
  { value: 'incorrect_location', label: t('Błędna lokalizacja') },
  { value: 'other', label: t('Inny problem') },
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
  if (!draft.category) errors.category = t('Wybierz rodzaj problemu.')
  if (length < DESCRIPTION_MIN) errors.description = t('Opisz problem w co najmniej {min} znakach.', { min: DESCRIPTION_MIN })
  if (length > DESCRIPTION_MAX) errors.description = t('Opis może mieć najwyżej {max} znaków.', { max: DESCRIPTION_MAX })
  return errors
}
