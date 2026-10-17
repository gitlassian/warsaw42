import { Text } from '@/design-system/components/Text'
import { WEEKDAY_NAMES } from '@/shared/lib/format'
import { formatInterval } from '../../lib/availability'
import type { Schedule } from '../../models/aed'
import styles from './AedHours.module.css'

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
        <Text tone="secondary">Niezweryfikowane. Godziny odczytane ze źródła, nie używamy ich do wskazywania dostępności.</Text>
        <AedHours schedule={unverified} />
        {sourceHours && <Text variant="meta" tone="muted">Wg źródła: {sourceHours}</Text>}
      </>
    )
  }
  if (schedule.kind === 'always_open') return <Text>Całodobowo, 7 dni w tygodniu</Text>
  if (schedule.kind === 'unknown') {
    return (
      <>
        <Text tone="secondary">Godziny nieznane</Text>
        {sourceHours && <Text variant="meta" tone="muted">Wg źródła: {sourceHours}</Text>}
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
              {intervals ? (intervals.length ? intervals.map(formatInterval).join(', ') : 'zamknięte') : 'nie podano w źródle'}
            </dd>
          </div>
        )
      })}
    </dl>
  )
}
