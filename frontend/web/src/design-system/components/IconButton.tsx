import type { ButtonHTMLAttributes } from 'react'
import { AppIcon, type IconName } from './AppIcon'
import styles from './IconButton.module.css'

type IconButtonProps = Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children' | 'aria-label'> & {
  icon: IconName
  /** Accessible name, also shown as a tooltip on web. */
  label: string
  /** floating: round map control; plain: inside a panel. */
  variant?: 'floating' | 'plain'
  pressed?: boolean
  /** Short visible caption under the icon (floating map controls), e.g. "Filtry". */
  text?: string
}

export function IconButton({ icon, label, variant = 'plain', pressed, text, ...rest }: IconButtonProps) {
  return (
    <button
      {...rest}
      type="button"
      className={text ? styles.tile : styles[variant]}
      aria-label={label}
      title={label}
      aria-pressed={pressed}
    >
      <AppIcon name={icon} filled={pressed} />
      {text && (
        <span className={styles.text} aria-hidden="true">
          {text}
        </span>
      )}
    </button>
  )
}
