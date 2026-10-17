import type { ReactNode } from 'react'
import { Text } from './Text'
import styles from './PanelHeader.module.css'

type PanelHeaderProps = {
  title: ReactNode
}

export function PanelHeader({ title }: PanelHeaderProps) {
  return (
    <header className={styles.header}>
      <Text variant="title" as="h2">
        {title}
      </Text>
    </header>
  )
}
