import type { ReactNode } from 'react'
import { IconButton } from './IconButton'
import { Text } from './Text'
import styles from './PanelHeader.module.css'

type PanelHeaderProps = {
  title?: ReactNode
  onBack?: () => void
}

export function PanelHeader({ title, onBack }: PanelHeaderProps) {
  return (
    <header className={styles.header}>
      {onBack && <IconButton icon="arrow_back" label="Wróć" onClick={onBack} />}
      {title && (
        <Text variant="title" as="h2">
          {title}
        </Text>
      )}
    </header>
  )
}
