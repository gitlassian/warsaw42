import { Link, useMatch, useNavigate } from 'react-router'
import { RoutePaths } from '@/app/routePaths'
import logo from '@/assets/brand/defiwawa-horizontal.svg'
import { IconButton } from '@/design-system/components/IconButton'
import styles from './AppHeader.module.css'

type AppHeaderProps = {
  /** Over the map, also in the wide layout. */
  floating?: boolean
  withInfo?: boolean
  /** Wide layout: closes the open AED or panel from the header row. */
  onClose?: () => void
}

/** Compact name, plus the info button on narrow screens or the open AED/panel's close button on wide ones (DESIGN.md §6). */
export function AppHeader({ floating = false, withInfo = true, onClose }: AppHeaderProps) {
  return (
    <header className={styles.header} data-floating={floating || undefined}>
      <Link to={RoutePaths.map} className={styles.brand}>
        <h1 className={styles.name}>
          <img src={logo} alt="DefiWawa" className={styles.logo} />
        </h1>
      </Link>
      {withInfo && <InfoButton />}
      {onClose && (
        <span className={styles.close}>
          <IconButton icon="close" label="Zamknij" onClick={onClose} />
        </span>
      )}
    </header>
  )
}

/** Opens "O danych" and closes it again: in the header on narrow screens, on top of the round map controls from 840 (captioned). */
export function InfoButton({ text }: { text?: string }) {
  const navigate = useNavigate()
  const shown = useMatch(RoutePaths.data) !== null
  return (
    <IconButton
      variant="floating"
      icon="info"
      label="O danych"
      text={text}
      pressed={shown}
      onClick={() => navigate(shown ? RoutePaths.map : RoutePaths.data)}
    />
  )
}
