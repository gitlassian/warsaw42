import type { ReactNode } from 'react'
import { AppIcon } from './AppIcon'
import styles from './Disclosure.module.css'

type DisclosureProps = {
  title: string
  children: ReactNode
}

/** Expandable section for secondary details (hours, source text, device info). */
export function Disclosure({ title, children }: DisclosureProps) {
  return (
    <details className={styles.details}>
      <summary className={styles.summary}>
        <span>{title}</span>
        <span className={styles.chevron}>
          <AppIcon name="expand_more" />
        </span>
      </summary>
      <div className={styles.content}>{children}</div>
    </details>
  )
}
