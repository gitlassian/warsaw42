import { useId, type HTMLAttributes, type ReactNode } from 'react'
import styles from './TextField.module.css'

type TextFieldProps = {
  label: string
  value: string
  onChange: (value: string) => void
  /** Visible help text below the label; a placeholder never replaces it. */
  hint?: ReactNode
  /** What to correct; shown below the field. */
  error?: string
  multiline?: boolean
  type?: 'text' | 'tel' | 'datetime-local'
  inputMode?: HTMLAttributes<HTMLInputElement>['inputMode']
  autoComplete?: string
  maxLength?: number
  autoFocus?: boolean
}

export function TextField({ label, value, onChange, hint, error, multiline, type = 'text', ...rest }: TextFieldProps) {
  const id = useId()
  const describedBy = [hint && `${id}-hint`, error && `${id}-error`].filter(Boolean).join(' ') || undefined
  const fieldProps = {
    ...rest,
    id,
    value,
    className: styles.field,
    'aria-invalid': error ? true : undefined,
    'aria-describedby': describedBy,
  }

  return (
    <div className={styles.wrapper}>
      <label htmlFor={id} className={styles.label}>
        {label}
      </label>
      {hint && (
        <p id={`${id}-hint`} className={styles.hint}>
          {hint}
        </p>
      )}
      {multiline ? (
        <textarea {...fieldProps} rows={4} onChange={(e) => onChange(e.target.value)} />
      ) : (
        <input {...fieldProps} type={type} onChange={(e) => onChange(e.target.value)} />
      )}
      {error && (
        <p id={`${id}-error`} className={styles.error}>
          {error}
        </p>
      )}
    </div>
  )
}
