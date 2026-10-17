import { Text } from '@/design-system/components/Text'
import { WEEKDAY_NAMES } from '@/shared/lib/format'
import { formatInterval } from '../../lib/availability'
import type { Schedule } from '../../models/aed'
import styles from './AedHours.module.css'

export function AedHours({ schedule }: { schedule: Schedule }) {
  if (schedule.kind === 'always_open') return <Text>Całodobowo, 7 dni w tygodniu</Text>
  if (schedule.kind === 'unknown') return <Text tone="secondary">Godziny nieznane</Text>
  return (
    <dl className={styles.hours}>
      {WEEKDAY_NAMES.map((day, i) => {
        const intervals = schedule.days[i]
        return (
          <div key={day} className={styles.row}>
            <dt>{day}</dt>
            <dd className={intervals ? undefined : styles.unknown}>
              {intervals ? intervals.map(formatInterval).join(', ') : 'nieznane'}
            </dd>
          </div>
        )
      })}
    </dl>
  )
}
