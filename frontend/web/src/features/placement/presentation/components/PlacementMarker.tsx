import styles from './PlacementMarker.module.css'

/** A suggested AED site: a green numbered disc, bigger when picked in the list. */
export function PlacementMarker({ rank, selected, onSelect }: { rank: number; selected: boolean; onSelect: () => void }) {
  return (
    <button
      type="button"
      className={styles.marker}
      aria-pressed={selected}
      aria-label={`Proponowane miejsce ${rank}`}
      onClick={onSelect}
    >
      {rank}
    </button>
  )
}
