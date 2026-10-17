import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent, type ReactNode } from 'react'
import { useMediaQuery } from '@/shared/hooks/useMediaQuery'
import { useViewportHeight } from '@/shared/hooks/useViewportHeight'
import { IconButton } from './IconButton'
import styles from './Sheet.module.css'

export type SheetSnap = 'compact' | 'medium' | 'expanded'

/** DESIGN.md §6: below 840 a bottom sheet, from 840 a side panel. */
export const WIDE_LAYOUT_QUERY = '(min-width: 840px)'

const SNAPS: SheetSnap[] = ['compact', 'medium', 'expanded']
const SNAP_FRACTION: Record<SheetSnap, number> = { compact: 0.32, medium: 0.7, expanded: 1 }
const MIN_HEIGHT = 168
const DRAG_THRESHOLD_PX = 6

type SheetProps = {
  label: string
  initialSnap?: SheetSnap
  /** Space kept free above the expanded sheet (app header). */
  topOffset?: number
  /** Height the sheet covers at the bottom of the screen; 0 in the wide layout. */
  onCoverChange?: (px: number) => void
  /** Shows a close button in the top-right corner. */
  onClose?: () => void
  children: ReactNode
}

export function Sheet({
  label,
  initialSnap = 'medium',
  topOffset = 80,
  onCoverChange,
  onClose,
  children,
}: SheetProps) {
  const wide = useMediaQuery(WIDE_LAYOUT_QUERY)
  const viewportHeight = useViewportHeight()
  const [snap, setSnap] = useState(initialSnap)
  const [dragHeight, setDragHeight] = useState<number | null>(null)
  const drag = useRef<{ startY: number; startHeight: number; moved: boolean } | null>(null)
  const suppressClick = useRef(false)

  const maxHeight = viewportHeight - topOffset
  const heightOf = (s: SheetSnap) => Math.min(maxHeight, Math.max(MIN_HEIGHT, Math.round(maxHeight * SNAP_FRACTION[s])))
  const height = dragHeight ?? heightOf(snap)
  const cover = wide ? 0 : height

  useEffect(() => onCoverChange?.(cover), [cover, onCoverChange])
  // Unmounted, the sheet no longer covers the map.
  useEffect(() => () => onCoverChange?.(0), [onCoverChange])

  const close = onClose && (
    <span className={styles.close}>
      <IconButton icon="close" label="Zamknij" onClick={onClose} />
    </span>
  )

  if (wide) {
    return (
      <aside className={styles.panel} aria-label={label}>
        {close}
        {children}
      </aside>
    )
  }

  const step = (direction: 1 | -1) => {
    const next = SNAPS[SNAPS.indexOf(snap) + direction]
    if (next) setSnap(next)
  }

  const onPointerDown = (e: PointerEvent<HTMLButtonElement>) => {
    drag.current = { startY: e.clientY, startHeight: height, moved: false }
    e.currentTarget.setPointerCapture(e.pointerId)
  }

  const onPointerMove = (e: PointerEvent<HTMLButtonElement>) => {
    const d = drag.current
    if (!d) return
    const dy = d.startY - e.clientY
    if (!d.moved && Math.abs(dy) < DRAG_THRESHOLD_PX) return
    d.moved = true
    setDragHeight(Math.min(maxHeight, Math.max(MIN_HEIGHT, d.startHeight + dy)))
  }

  const onPointerUp = () => {
    const moved = drag.current?.moved
    drag.current = null
    if (!moved || dragHeight === null) return
    suppressClick.current = true
    setSnap(SNAPS.reduce((best, s) => (Math.abs(heightOf(s) - dragHeight) < Math.abs(heightOf(best) - dragHeight) ? s : best)))
    setDragHeight(null)
  }

  const onClick = () => {
    if (suppressClick.current) {
      suppressClick.current = false
      return
    }
    setSnap(snap === 'expanded' ? 'medium' : snap === 'medium' ? 'expanded' : 'medium')
  }

  const onKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      e.preventDefault()
      step(e.key === 'ArrowUp' ? 1 : -1)
    }
  }

  return (
    <section className={styles.sheet} style={{ height }} data-dragging={dragHeight !== null || undefined} aria-label={label}>
      <button
        type="button"
        className={styles.handle}
        aria-label={snap === 'expanded' ? 'Zwiń szczegóły' : 'Pokaż szczegóły'}
        aria-expanded={snap === 'expanded'}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onClick={onClick}
        onKeyDown={onKeyDown}
      >
        <span className={styles.grip} />
      </button>
      {close}
      <div className={styles.content}>{children}</div>
    </section>
  )
}
