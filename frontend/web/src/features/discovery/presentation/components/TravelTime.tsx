import { formatDistance, formatDuration } from '@/shared/lib/format'
import type { EtaEntry } from '../../models/routing'
import styles from './TravelTime.module.css'

type TravelTimeProps = {
  eta?: EtaEntry
  /** Shown only when there is no walking time, always labeled as straight-line. */
  straightLineM?: number | null
  size?: 'hero' | 'row'
}

/** Walking time "4 min pieszo · 280 m"; never presents straight-line distance as walking. */
export function TravelTime({ eta, straightLineM, size = 'row' }: TravelTimeProps) {
  const className = `${styles.travel} ${styles[size]}`
  if (eta === 'loading') {
    return (
      <span className={className}>
        <span className={styles.placeholder} />
        <span className="visually-hidden">Obliczamy czas dojścia</span>
      </span>
    )
  }
  if (eta?.status === 'ok') {
    return (
      <span className={className}>
        <strong className={styles.time}>{formatDuration(eta.durationSeconds)} pieszo</strong>
        <span>· {formatDistance(eta.distanceM)}</span>
      </span>
    )
  }
  if (eta) {
    return (
      <span className={className}>
        <strong className={styles.time} aria-hidden="true">
          —
        </strong>
        <span className={styles.note}>Nie udało się obliczyć czasu</span>
      </span>
    )
  }
  if (straightLineM == null) return null
  return (
    <span className={`${className} ${styles.straight}`}>
      {formatDistance(straightLineM)} <span className={styles.note}>w linii prostej</span>
    </span>
  )
}
