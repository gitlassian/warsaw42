import type { IconName } from '@/design-system/components/AppIcon'
import type { Tone } from '@/design-system/tone'
import type { Aed } from '../models/aed'
import { evaluateHours } from './availability'
import { t } from '../../../i18n/index.ts'

export type AedStatus = {
  tone: Tone
  icon: IconName
  /** Short access status (DESIGN.md §3), e.g. "Dostępny do 18:00". */
  label: string
  /** Next known change when the label does not say it, e.g. "Otwarcie o 08:00". */
  detail: string | null
  /** Open according to known hours and public: the only status shown as available. */
  available: boolean
}

/** Access status at `at`. Device condition wins over hours; hours never confirm the device works. */
export function aedStatus(aed: Aed, at: Date): AedStatus {
  if (aed.operationalStatus === 'confirmed_unavailable') {
    return { tone: 'danger', icon: 'error', label: t('AED niedostępny'), detail: null, available: false }
  }
  if (aed.publicAccess === 'restricted') {
    return { tone: 'warning', icon: 'warning', label: t('Dostęp niepotwierdzony'), detail: null, available: false }
  }
  // No information means unavailable.
  if (aed.publicAccess === 'unknown') {
    return { tone: 'neutral', icon: 'lock', label: t('Niedostępny'), detail: t('Brak informacji o dostępie'), available: false }
  }
  const hours = evaluateHours(aed.schedule, at)
  switch (hours.state) {
    case 'open':
      return hours.until
        ? { tone: 'accent', icon: 'check_circle', label: t('Dostępny do {time}', { time: hours.until }), detail: null, available: true }
        : { tone: 'accent', icon: 'check_circle', label: t('Dostęp całodobowy'), detail: null, available: true }
    case 'closed':
      return {
        tone: 'neutral',
        icon: 'lock',
        label: t('Teraz zamknięty'),
        detail: hours.opensAt ? t('Otwarcie o {time}', { time: hours.opensAt }) : null,
        available: false,
      }
    case 'unknown':
      return {
        tone: 'neutral',
        icon: 'lock',
        label: t('Niedostępny'),
        detail: sourceHoursDetail(aed.sourceHours) ?? t('Brak informacji o godzinach'),
        available: false,
      }
  }
}

/** The source wording stays visible when it could not be turned into checked hours. */
function sourceHoursDetail(text: string | null): string | null {
  const source = text?.replace(/\s+/g, ' ').trim()
  if (!source) return null
  return t('Wg źródła: {text}', { text: source.length > 70 ? `${source.slice(0, 67)}…` : source })
}

/** Indoor/outdoor placement with the floor when known. */
export function placementLabel(aed: Aed): string {
  const place = aed.indoor ? t('Wewnątrz budynku') : t('Na zewnątrz')
  if (aed.floor === null) return place
  return `${place}, ${aed.floor === 0 ? t('parter') : aed.floor > 0 ? t('piętro {n}', { n: aed.floor }) : t('poziom {n}', { n: aed.floor })}`
}
