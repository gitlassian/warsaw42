import type { IconName } from '@/design-system/components/AppIcon'
import type { Tone } from '@/design-system/tone'
import type { Aed } from '../models/aed'
import { evaluateHours } from './availability'

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
    return { tone: 'danger', icon: 'error', label: 'AED niedostępny', detail: null, available: false }
  }
  if (aed.publicAccess === 'restricted') {
    return { tone: 'warning', icon: 'warning', label: 'Dostęp niepotwierdzony', detail: null, available: false }
  }
  // No information means unavailable.
  if (aed.publicAccess === 'unknown') {
    return { tone: 'neutral', icon: 'lock', label: 'Niedostępny', detail: 'Brak informacji o dostępie', available: false }
  }
  const hours = evaluateHours(aed.schedule, at)
  switch (hours.state) {
    case 'open':
      return hours.until
        ? { tone: 'accent', icon: 'check_circle', label: `Dostępny do ${hours.until}`, detail: null, available: true }
        : { tone: 'accent', icon: 'check_circle', label: 'Dostęp całodobowy', detail: null, available: true }
    case 'closed':
      return {
        tone: 'neutral',
        icon: 'lock',
        label: 'Teraz zamknięty',
        detail: hours.opensAt ? `Otwarcie o ${hours.opensAt}` : null,
        available: false,
      }
    case 'unknown':
      return {
        tone: 'neutral',
        icon: 'lock',
        label: 'Niedostępny',
        detail: sourceHoursDetail(aed.sourceHours) ?? 'Brak informacji o godzinach',
        available: false,
      }
  }
}

/** The source wording stays visible when it could not be turned into checked hours. */
function sourceHoursDetail(text: string | null): string | null {
  const t = text?.replace(/\s+/g, ' ').trim()
  if (!t) return null
  return `Wg źródła: ${t.length > 70 ? `${t.slice(0, 67)}…` : t}`
}

/** Indoor/outdoor placement with the floor when known. */
export function placementLabel(aed: Aed): string {
  const place = aed.indoor ? 'Wewnątrz budynku' : 'Na zewnątrz'
  if (aed.floor === null) return place
  return `${place}, ${aed.floor === 0 ? 'parter' : aed.floor > 0 ? `piętro ${aed.floor}` : `poziom ${aed.floor}`}`
}
