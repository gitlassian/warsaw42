import type { ReactNode } from 'react'
import { TONE_ICON, toneClass, type Tone } from '../tone'
import { AppIcon, type IconName } from './AppIcon'
import styles from './Notice.module.css'

type NoticeProps = {
  tone?: Tone
  icon?: IconName
  title: string
  children?: ReactNode
  /** The next step the user can take, e.g. a retry button. */
  actions?: ReactNode
}

/** In-panel message that stays until the situation is resolved (DESIGN.md §8). */
export function Notice({ tone = 'neutral', icon, title, children, actions }: NoticeProps) {
  return (
    <div className={`${styles.notice} ${toneClass[tone]}`} role={tone === 'danger' ? 'alert' : 'status'}>
      <span className={styles.icon}>
        <AppIcon name={icon ?? TONE_ICON[tone]} />
      </span>
      <div className={styles.body}>
        <p className={styles.title}>{title}</p>
        {children && <div className={styles.text}>{children}</div>}
        {actions && <div className={styles.actions}>{actions}</div>}
      </div>
    </div>
  )
}
