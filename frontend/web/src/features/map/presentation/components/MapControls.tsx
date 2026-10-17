import { IconButton } from '@/design-system/components/IconButton'
import type { AedAvailability, AedFilters } from '@/features/aeds/lib/aedAvailability'
import { FilterMenu } from './FilterMenu'
import styles from './MapControls.module.css'

type MapControlsProps = {
  locating: boolean
  coverageShown: boolean
  filters: AedFilters
  timeOpen: boolean
  filtersOpen: boolean
  onLocate: () => void
  onToggleCoverage: () => void
  onToggleFilter: (group: AedAvailability) => void
  onToggleTime: () => void
  onFiltersOpenChange: (open: boolean) => void
}

/** Round floating controls; positioned around the sheet by the page. */
export function MapControls({
  locating,
  coverageShown,
  filters,
  timeOpen,
  filtersOpen,
  onLocate,
  onToggleCoverage,
  onToggleFilter,
  onToggleTime,
  onFiltersOpenChange,
}: MapControlsProps) {
  return (
    <div className={styles.controls}>
      <IconButton
        variant="floating"
        icon="my_location"
        label="Pokaż moją lokalizację"
        text="Pozycja"
        onClick={onLocate}
        disabled={locating}
      />
      <IconButton
        variant="floating"
        icon="layers"
        label="Warstwa: Odległość do najbliższego AED"
        text="Zasięg"
        pressed={coverageShown}
        onClick={onToggleCoverage}
      />
      <IconButton
        variant="floating"
        icon="schedule"
        label={timeOpen ? 'Ukryj wybór godziny' : 'Sprawdź dostępność o innej porze'}
        text="Pora"
        pressed={timeOpen}
        onClick={onToggleTime}
      />
      <FilterMenu filters={filters} onToggle={onToggleFilter} open={filtersOpen} onOpenChange={onFiltersOpenChange} />
    </div>
  )
}
