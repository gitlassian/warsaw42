import { IconButton } from '@/design-system/components/IconButton'
import styles from './PickOriginBanner.module.css'
import { t } from '@/i18n'

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
        <strong>{t('Wybierz punkt na mapie')}</strong>
        <span className={outside ? styles.error : undefined}>
          {outside ? t('Ten punkt jest poza Warszawą. Wybierz punkt w granicach miasta.') : t('Dotknij mapy w miejscu startu.')}
        </span>
      </p>
      <IconButton icon="close" label={t('Anuluj wybór punktu')} onClick={onCancel} />
    </div>
  )
}
