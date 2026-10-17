import { Link } from 'react-router'
import { AppIcon } from '@/design-system/components/AppIcon'
import { toneClass } from '@/design-system/tone'
import type { AedStatus } from '@/features/aeds/lib/aedStatus'
import type { Aed } from '@/features/aeds/models/aed'
import type { EtaEntry } from '@/features/discovery/models/routing'
import { formatDuration } from '@/shared/lib/format'
import styles from './MapMarkers.module.css'
import { intlLocale, locale, t } from '@/i18n'

type AedMarkerProps = {
  aed: Aed
  status: AedStatus
  to: string
  /** Shown as a pill only when there is an origin (DESIGN.md §7). */
  eta?: EtaEntry
  selected?: boolean
}

function etaText(eta: EtaEntry | undefined): { pill: string | null; spoken: string | null } {
  if (!eta) return { pill: null, spoken: null }
  if (eta === 'loading') return { pill: null, spoken: t('obliczamy czas dojścia') }
  if (eta.status === 'ok') {
    const time = formatDuration(eta.durationSeconds)
    return { pill: time, spoken: t('{time} pieszo', { time }) }
  }
  return { pill: '—', spoken: t('nie udało się obliczyć czasu') }
}

/** Compact AED pin: outline color + status icon for access (the name is in the accessible label), optional walking-time pill. */
export function AedMarker({ aed, status, to, eta, selected }: AedMarkerProps) {
  const { pill, spoken } = etaText(eta)
  return (
    <Link
      to={to}
      className={`${styles.aed} ${toneClass[status.tone]}`}
      aria-current={selected || undefined}
      aria-label={['AED', aed.venueName, status.label, spoken].filter(Boolean).join(', ')}
    >
      <span className={styles.pin}>
        <AppIcon name="aed" size={20} />
        <span className={styles.status}>
          <AppIcon name={status.icon} size={16} />
        </span>
      </span>
      {eta && (
        <span className={styles.pill} aria-hidden="true">
          {eta === 'loading' ? <span className={styles.placeholder} /> : pill}
        </span>
      )}
    </Link>
  )
}

const PLURAL = new Intl.PluralRules(intlLocale)

/** Several AEDs close together: the count, green when at least one is available now. A tap zooms in. */
export function ClusterMarker({ count, available, onExpand }: { count: number; available: number; onExpand: () => void }) {
  const plural = PLURAL.select(count)
  const where =
    locale === 'en'
      ? t(plural === 'one' ? '{count} defibrillator in this place' : '{count} defibrillators in this place', { count })
      : `${count} ${plural === 'few' ? 'defibrylatory' : 'defibrylatorów'} w tym miejscu`
  const nowAvailable = available > 0 ? t(', w tym dostępne teraz: {available}', { available }) : ''
  return (
    <button
      type="button"
      className={styles.cluster}
      data-available={available > 0 || undefined}
      onClick={onExpand}
      aria-label={`${where}${nowAvailable}. ${t('Przybliż mapę.')}`}
    >
      {count}
    </button>
  )
}

/** GPS: blue dot. A picked start point: a pin, never a GPS dot (DESIGN.md §7). */
/** Navigation: the walker as an arrow pointing along the route, laid flat on the map. */
export function HeadingMarker() {
  return (
    <svg className={styles.heading} viewBox="0 0 24 24" width="56" height="56" role="img" aria-label={t('Twoja lokalizacja i kierunek')}>
      <path d="M12 2.5 20 21l-8-4.2L4 21z" />
    </svg>
  )
}

export function OriginMarker({ source }: { source: 'gps' | 'manual' }) {
  return source === 'gps' ? (
    <span className={styles.gps} role="img" aria-label={t('Twoja lokalizacja')} />
  ) : (
    <span className={styles.origin} role="img" aria-label={t('Wybrany punkt startowy')}>
      <AppIcon name="location_on" size={32} />
    </span>
  )
}
