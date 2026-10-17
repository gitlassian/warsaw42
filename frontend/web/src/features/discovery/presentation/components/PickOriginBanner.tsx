import { IconButton } from '@/design-system/components/IconButton'
import styles from './PickOriginBanner.module.css'

type PickOriginBannerProps = {
  /** The last tapped point was outside Warsaw. */
  outside: boolean
  onCancel: () => void
}

/** Shown over the map while the user picks a start point. */
export function PickOriginBanner({ outside, onCancel }: PickOriginBannerProps) {
  return (
    <div className={styles.banner} role="status">
      <p className={styles.text}>
        <strong>Wybierz punkt na mapie</strong>
        <span className={outside ? styles.error : undefined}>
          {outside ? 'Ten punkt jest poza Warszawą. Wybierz punkt w granicach miasta.' : 'Dotknij mapy w miejscu startu.'}
        </span>
      </p>
      <IconButton icon="close" label="Anuluj wybór punktu" onClick={onCancel} />
    </div>
  )
}
