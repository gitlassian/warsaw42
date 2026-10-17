import type { ReactNode } from 'react'
import { toneClass, type Tone } from '../tone'
import { AppIcon, type IconName } from './AppIcon'
import styles from './StatusText.module.css'

/** Status as colored text without a chip: the words carry the meaning, the tone color reinforces it. */
export function StatusText({ tone, icon, children }: { tone: Tone; icon?: IconName; children: ReactNode }) {
  return (
    <span className={`${styles.status} ${toneClass[tone]}`}>
      {icon && <AppIcon name={icon} size={20} />}
      {children}
    </span>
  )
}
