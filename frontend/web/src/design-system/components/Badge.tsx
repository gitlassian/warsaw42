import type { ReactNode } from 'react'
import { toneClass, type Tone } from '../tone'
import { AppIcon, type IconName } from './AppIcon'
import styles from './Badge.module.css'

type BadgeProps = {
  tone: Tone
  icon: IconName
  children: ReactNode
}

/** Status label: color, icon and text together (DESIGN.md §1). */
export function Badge({ tone, icon, children }: BadgeProps) {
  return (
    <span className={`${styles.badge} ${toneClass[tone]}`}>
      <AppIcon name={icon} size={20} />
      {children}
    </span>
  )
}
