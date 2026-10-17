import { IconButton } from '@/design-system/components/IconButton'
import styles from './MapControls.module.css'

type MapControlsProps = {
  locating: boolean
  coverageShown: boolean
  onLocate: () => void
  onToggleCoverage: () => void
}

/** Round floating controls; positioned around the sheet by the page. */
export function MapControls({ locating, coverageShown, onLocate, onToggleCoverage }: MapControlsProps) {
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
    </div>
  )
}
