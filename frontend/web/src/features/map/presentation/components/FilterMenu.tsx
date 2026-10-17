import { useEffect, useId, useRef } from 'react'
import { AppIcon, type IconName } from '@/design-system/components/AppIcon'
import { IconButton } from '@/design-system/components/IconButton'
import type { AedAvailability, AedFilters } from '@/features/aeds/lib/aedAvailability'
import styles from './FilterMenu.module.css'

const OPTIONS: { group: AedAvailability; icon: IconName; label: string }[] = [
  { group: 'available', icon: 'check_circle', label: 'Otwarte' },
  { group: 'unavailable', icon: 'lock', label: 'Zamknięte i niedostępne' },
]

type FilterMenuProps = {
  filters: AedFilters
  onToggle: (group: AedAvailability) => void
  /** Controlled by the page, so only one pop-up by the round controls is open at a time. */
  open: boolean
  onOpenChange: (open: boolean) => void
}

/** Dropdown of AED groups: green = shown, white = off; with every group off the map shows all AEDs. */
export function FilterMenu({ filters, onToggle, open, onOpenChange }: FilterMenuProps) {
  const rootRef = useRef<HTMLDivElement>(null)
  const menuId = useId()
  const anyOn = OPTIONS.some((o) => filters[o.group])

  useEffect(() => {
    if (!open) return
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      onOpenChange(false)
      rootRef.current?.querySelector<HTMLButtonElement>('[aria-controls]')?.focus()
    }
    const onPointerDown = (e: PointerEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) onOpenChange(false)
    }
    document.addEventListener('keydown', onKeyDown)
    document.addEventListener('pointerdown', onPointerDown)
    return () => {
      document.removeEventListener('keydown', onKeyDown)
      document.removeEventListener('pointerdown', onPointerDown)
    }
  }, [open, onOpenChange])

  return (
    <div ref={rootRef} className={styles.anchor}>
      <IconButton
        variant="floating"
        icon="filter_list"
        label="Filtry AED"
        pressed={open}
        aria-expanded={open}
        aria-controls={menuId}
        onClick={() => onOpenChange(!open)}
      />
      {open && (
        <div id={menuId} className={styles.menu} role="group" aria-label="Filtry AED">
          {OPTIONS.map(({ group, icon, label }) => (
            <button
              key={group}
              type="button"
              className={styles.option}
              aria-pressed={filters[group]}
              onClick={() => onToggle(group)}
            >
              <AppIcon name={icon} />
              {label}
            </button>
          ))}
          <p className={styles.hint}>{anyOn ? 'Pokazujemy tylko zaznaczone grupy.' : 'Brak filtrów: pokazujemy wszystkie AED.'}</p>
        </div>
      )}
    </div>
  )
}
