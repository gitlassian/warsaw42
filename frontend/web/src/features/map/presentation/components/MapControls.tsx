import { type ReactNode, useState } from 'react'
import { AppIcon } from '@/design-system/components/AppIcon'
import { IconButton } from '@/design-system/components/IconButton'
import type { AedAvailability, AedFilters } from '@/features/aeds/lib/aedAvailability'
import { FilterMenu } from './FilterMenu'
import styles from './MapControls.module.css'
import { t } from '@/i18n'

type MapControlsProps = {
  /** Narrow only: layers, time and filters fold behind a small "more" button. */
  collapsible?: boolean
  coverageShown: boolean
  placementShown: boolean
  filters: AedFilters
  timeOpen: boolean
  filtersOpen: boolean
  onToggleCoverage: () => void
  onTogglePlacement: () => void
  onToggleFilter: (group: AedAvailability) => void
  onToggleTime: () => void
  onFiltersOpenChange: (open: boolean) => void
  /** Narrow: shown right above the "more" button; hidden while the tiles are unfolded. */
  children?: ReactNode
}

/** Floating map controls (layers, time, filters); positioned around the sheet by the page. */
export function MapControls({
  collapsible,
  coverageShown,
  placementShown,
  filters,
  timeOpen,
  filtersOpen,
  onToggleCoverage,
  onTogglePlacement,
  onToggleFilter,
  onToggleTime,
  onFiltersOpenChange,
  children,
}: MapControlsProps) {
  const [moreOpen, setMoreOpen] = useState(false)
  const moreLabel = moreOpen ? t('Ukryj opcje mapy') : t('Więcej opcji mapy')

  return (
    <div className={styles.controls}>
      {(!collapsible || moreOpen) && (
        <div className={collapsible ? styles.unfolded : styles.controls}>
          <IconButton
            variant="floating"
            icon="layers"
            label={t('Warstwa: Odległość do najbliższego AED')}
            text={t('Zasięg')}
            pressed={coverageShown}
            onClick={onToggleCoverage}
          />
          <IconButton
            variant="floating"
            icon="add_location"
            label="Gdzie dodać AED: miejsca, które poprawią zasięg o wybranej porze"
            text="Nowe"
            pressed={placementShown}
            onClick={onTogglePlacement}
          />
          <IconButton
            variant="floating"
            icon="schedule"
            label={timeOpen ? t('Ukryj wybór godziny') : t('Sprawdź dostępność o innej porze')}
            text={t('Pora')}
            pressed={timeOpen}
            onClick={onToggleTime}
          />
          <FilterMenu filters={filters} onToggle={onToggleFilter} open={filtersOpen} onOpenChange={onFiltersOpenChange} />
        </div>
      )}
      {!moreOpen && children}
      {collapsible && (
        <button
          type="button"
          className={styles.more}
          aria-label={moreLabel}
          title={moreLabel}
          aria-expanded={moreOpen}
          onClick={() => setMoreOpen(!moreOpen)}
        >
          {/* Keyed so the glyph remounts and replays its turn-in on every toggle. */}
          <span key={moreOpen ? 'close' : 'more'} className={styles.moreIcon}>
            {moreOpen ? <AppIcon name="close" /> : <AppIcon name="more" size={32} />}
          </span>
        </button>
      )}
    </div>
  )
}
