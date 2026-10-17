import type { ElementType, ReactNode } from 'react'
import styles from './Text.module.css'

/** Type roles from DESIGN.md §3. */
export type TextVariant = 'time' | 'title' | 'name' | 'heading' | 'body' | 'label' | 'meta'

type TextProps = {
  variant?: TextVariant
  tone?: 'default' | 'secondary' | 'muted' | 'accent'
  as?: ElementType
  id?: string
  children: ReactNode
}

export function Text({ variant = 'body', tone = 'default', as: Tag = 'p', id, children }: TextProps) {
  return (
    <Tag id={id} className={`${styles[variant]} ${styles[tone]}`}>
      {children}
    </Tag>
  )
}
