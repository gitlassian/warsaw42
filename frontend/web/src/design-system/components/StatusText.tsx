import type { ReactNode } from 'react'
import { toneClass, type Tone } from '../tone'
import styles from './StatusText.module.css'

/** Status as colored text without a chip: the words carry the meaning, the tone color reinforces it. */
export function StatusText({ tone, children }: { tone: Tone; children: ReactNode }) {
  return <span className={`${styles.status} ${toneClass[tone]}`}>{children}</span>
}
