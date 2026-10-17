import { Link } from 'react-router'
import { RoutePaths } from '@/app/routePaths'
import logo from '@/assets/brand/defiwawa-horizontal.svg'
import { t } from '@/i18n'
import { IconButton } from '@/design-system/components/IconButton'
import styles from './AppHeader.module.css'

type AppHeaderProps = {
  /** Over the map, also in the wide layout. */
  floating?: boolean
  /** Wide layout: closes the open AED or panel from the header row. */
  onClose?: () => void
}

/** Compact name, plus the open AED/panel's close button on wide screens (DESIGN.md §6). */
export function AppHeader({ floating = false, onClose }: AppHeaderProps) {
  return (
    <header className={styles.header} data-floating={floating || undefined}>
      {/* Start screen: the D in the search field is the logo, the lockup stays only as the page heading. */}
      {floating ? (
        <h1 className={styles.srOnly}>DefiWawa</h1>
      ) : (
        <Link to={RoutePaths.map} className={styles.brand}>
          <h1 className={styles.name}>
            <img src={logo} alt="DefiWawa" className={styles.logo} />
          </h1>
        </Link>
      )}
      <span className={styles.end}>
        {onClose && (
          <span className={styles.close}>
            <IconButton icon="close" label={t('Zamknij')} onClick={onClose} />
          </span>
        )}
      </span>
    </header>
  )
}

