import { IconButton } from '@/design-system/components/IconButton'
import type { AedAvailability, AedFilters } from '@/features/aeds/lib/aedAvailability'
import { FilterMenu } from './FilterMenu'
import styles from './MapControls.module.css'

type MapControlsProps = {
  locating: boolean
  coverageShown: boolean
  filters: AedFilters
  onLocate: () => void
  onToggleCoverage: () => void
  onToggleFilter: (group: AedAvailability) => void
}

/** Round floating controls; positioned around the sheet by the page. */
export function MapControls({ locating, coverageShown, filters, onLocate, onToggleCoverage, onToggleFilter }: MapControlsProps) {
  return (
    <div className={styles.controls}>
      <IconButton
        variant="floating"
        icon="my_location"
        label="Pokaż moją lokalizację"
        onClick={onLocate}
        disabled={locating}
      />
      <IconButton
        variant="floating"
        icon="layers"
        label="Warstwa: Zasięg AED"
        pressed={coverageShown}
        onClick={onToggleCoverage}
      />
      <FilterMenu filters={filters} onToggle={onToggleFilter} />
    </div>
  )
}
