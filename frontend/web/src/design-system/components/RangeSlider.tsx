import type { InputHTMLAttributes } from 'react'
import styles from './RangeSlider.module.css'

type RangeSliderProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'type' | 'min' | 'max' | 'value' | 'onChange'> & {
  min: number
  max: number
  value: number
  onChange: (value: number) => void
  /** Shown right under the two ends of the track. */
  minLabel: string
  maxLabel: string
}

/** Range input with its first and last value labelled just below the track. */
export function RangeSlider({ min, max, value, onChange, minLabel, maxLabel, ...rest }: RangeSliderProps) {
  return (
    <div className={styles.range}>
      <input
        {...rest}
        type="range"
        className={styles.slider}
        min={min}
        max={max}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
      />
      <div className={styles.scale} aria-hidden="true">
        <span>{minLabel}</span>
        <span>{maxLabel}</span>
      </div>
    </div>
  )
}
