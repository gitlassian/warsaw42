import { useId } from 'react'
import styles from './ChoiceGroup.module.css'

type ChoiceGroupProps<T extends string | number> = {
  legend: string
  options: readonly { value: T; label: string }[]
  value: T | null
  onChange: (value: T) => void
  /** list: one option per row; inline: short options side by side. */
  layout?: 'list' | 'inline'
  error?: string
}

/** Native radio group styled as selectable rows. */
export function ChoiceGroup<T extends string | number>({
  legend,
  options,
  value,
  onChange,
  layout = 'list',
  error,
}: ChoiceGroupProps<T>) {
  const name = useId()
  return (
    <fieldset className={styles.group} aria-invalid={error ? true : undefined}>
      <legend className={styles.legend}>{legend}</legend>
      <div className={styles[layout]}>
        {options.map((option) => (
          <label key={option.value} className={styles.option}>
            <input
              type="radio"
              name={name}
              checked={option.value === value}
              onChange={() => onChange(option.value)}
            />
            <span>{option.label}</span>
          </label>
        ))}
      </div>
      {error && <p className={styles.error}>{error}</p>}
    </fieldset>
  )
}
