import { Text } from '@/design-system/components/Text'
import { WEEKDAY_NAMES } from '@/shared/lib/format'
import { formatInterval } from '../../lib/availability'
import type { Schedule } from '../../models/aed'
import styles from './AedHours.module.css'
import { t } from '@/i18n'

export function AedHours({
  schedule,
  sourceHours,
  unverified,
}: {
  schedule: Schedule
  sourceHours?: string | null
  unverified?: Schedule | null
}) {
  if (schedule.kind === 'unknown' && unverified && unverified.kind !== 'unknown') {
    return (
      <>
        <Text tone="secondary">
          {t('Niezweryfikowane. Godziny odczytane ze źródła, nie używamy ich do wskazywania dostępności.')}
        </Text>
        <AedHours schedule={unverified} />
        {sourceHours && <Text variant="meta" tone="muted">{t('Wg źródła:')} {sourceHours}</Text>}
      </>
    )
  }
  if (schedule.kind === 'always_open') return <Text>{t('Całodobowo, 7 dni w tygodniu')}</Text>
  if (schedule.kind === 'unknown') {
    return (
      <>
        <Text tone="secondary">{t('Brak informacji o godzinach, więc traktujemy AED jako niedostępny.')}</Text>
        {sourceHours && <Text variant="meta" tone="muted">{t('Wg źródła:')} {sourceHours}</Text>}
      </>
    )
  }
  return (
    <dl className={styles.hours}>
      {WEEKDAY_NAMES.map((day, i) => {
        const intervals = schedule.days[i]
        return (
          <div key={day} className={styles.row}>
            <dt>{day}</dt>
            <dd className={intervals ? undefined : styles.unknown}>
              {intervals ? (intervals.length ? intervals.map(formatInterval).join(', ') : t('zamknięte')) : t('niedostępny (brak danych)')}
            </dd>
          </div>
        )
      })}
    </dl>
  )
}
