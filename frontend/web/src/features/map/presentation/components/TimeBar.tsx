import { warsawClock } from '@/features/aeds/lib/availability'
import { WEEKDAY_NAMES } from '@/shared/lib/format'
import styles from './TimeBar.module.css'

const DAY_SHORT = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd']
const STEP_MIN = 15

const clock = (minutes: number) => `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`

type TimeBarProps = {
  at: Date
  live: boolean
  onChange: (day: number, minutes: number) => void
  onNow: () => void
}

/** Weekday chips and a time slider: shows which AEDs are available at any hour of the week. */
export function TimeBar({ at, live, onChange, onNow }: TimeBarProps) {
  const { day, minutes } = warsawClock(at)
  const sliderValue = Math.floor(minutes / STEP_MIN) * STEP_MIN
  return (
    <div className={styles.bar} role="group" aria-label="Podgląd dostępności o wybranej porze">
      <div className={styles.top}>
        <span className={styles.label}>
          {live ? 'Teraz' : WEEKDAY_NAMES[day]}, {clock(minutes)}
        </span>
        {!live && (
          <button type="button" className={styles.now} onClick={onNow}>
            Teraz
          </button>
        )}
      </div>
      <div className={styles.days}>
        {DAY_SHORT.map((name, i) => (
          <button
            key={name}
            type="button"
            className={styles.day}
            aria-pressed={i === day}
            aria-label={WEEKDAY_NAMES[i]}
            onClick={() => onChange(i, sliderValue)}
          >
            {name}
          </button>
        ))}
      </div>
      <input
        className={styles.slider}
        type="range"
        min={0}
        max={24 * 60 - STEP_MIN}
        step={STEP_MIN}
        value={sliderValue}
        aria-label="Godzina"
        aria-valuetext={clock(sliderValue)}
        onChange={(e) => onChange(day, Number(e.target.value))}
      />
      {!live && <p className={styles.hint}>Podgląd godzin dostępu. Trasy liczymy dla chwili obecnej.</p>}
    </div>
  )
}
