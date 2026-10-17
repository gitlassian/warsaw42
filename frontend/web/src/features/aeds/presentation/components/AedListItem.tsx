import type { ReactNode } from 'react'
import { Link } from 'react-router'
import { Badge } from '@/design-system/components/Badge'
import type { AedStatus } from '../../lib/aedStatus'
import type { Aed } from '../../models/aed'
import styles from './AedListItem.module.css'

type AedListItemProps = {
  aed: Aed
  status: AedStatus
  to: string
  /** Walking time or distance, rendered by the caller. */
  travel?: ReactNode
  selected?: boolean
}

export function AedListItem({ aed, status, to, travel, selected }: AedListItemProps) {
  return (
    <li>
      <Link to={to} className={styles.row} aria-current={selected || undefined}>
        {travel}
        <span className={styles.name}>{aed.venueName}</span>
        <span className={styles.address}>{aed.address}</span>
        <Badge tone={status.tone} icon={status.icon}>
          {status.label}
        </Badge>
      </Link>
    </li>
  )
}
