import { warsawClock } from '@/features/aeds/lib/availability'
import { WEEKDAY_NAMES } from '@/shared/lib/format'
import { RangeSlider } from '@/design-system/components/RangeSlider'
import styles from './TimeBar.module.css'
import { t } from '@/i18n'

const DAY_SHORT = [t('Pn'), t('Wt'), t('Śr'), t('Cz'), t('Pt'), t('So'), t('Nd')]
const STEP_MIN = 15
const LAST_STEP = 24 * 60 - STEP_MIN

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
    <div className={styles.bar} role="group" aria-label={t('Podgląd dostępności o wybranej porze')}>
      <div className={styles.top}>
        <span className={styles.label}>
          {live ? t('Teraz') : WEEKDAY_NAMES[day]}, {clock(minutes)}
        </span>
        {!live && (
          <button type="button" className={styles.now} onClick={onNow}>
            {t('Teraz')}
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
      <RangeSlider
        min={0}
        max={LAST_STEP}
        step={STEP_MIN}
        value={sliderValue}
        aria-label={t('Godzina')}
        aria-valuetext={clock(sliderValue)}
        onChange={(value) => onChange(day, value)}
        minLabel={clock(0)}
        maxLabel={clock(LAST_STEP)}
      />
      {!live && <p className={styles.hint}>{t('Podgląd godzin dostępu. Trasy liczymy dla chwili obecnej.')}</p>}
    </div>
  )
}
