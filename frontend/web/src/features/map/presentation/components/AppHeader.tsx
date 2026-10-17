import { Link } from 'react-router'
import { RoutePaths } from '@/app/routePaths'
import logo from '@/assets/brand/defiwawa-horizontal.svg'
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
      <Link to={RoutePaths.map} className={styles.brand}>
        <h1 className={styles.name}>
          <img src={logo} alt="DefiWawa" className={styles.logo} />
        </h1>
      </Link>
      {onClose && (
        <span className={styles.close}>
          <IconButton icon="close" label="Zamknij" onClick={onClose} />
        </span>
      )}
    </header>
  )
}

