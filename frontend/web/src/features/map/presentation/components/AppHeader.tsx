import { useEffect, useId, useRef, useState } from 'react'
import { Link, NavLink } from 'react-router'
import { RoutePaths } from '@/app/routePaths'
import logo from '@/assets/brand/defiwawa-horizontal.svg'
import { AppIcon, type IconName } from '@/design-system/components/AppIcon'
import { IconButton } from '@/design-system/components/IconButton'
import styles from './AppHeader.module.css'

const MENU: { to: string; icon: IconName; label: string }[] = [
  { to: RoutePaths.aeds, icon: 'list', label: 'Defibrylatory w pobliżu' },
  { to: RoutePaths.coverage, icon: 'layers', label: 'Zasięg AED' },
  { to: RoutePaths.offline, icon: 'download', label: 'Mapa offline' },
  { to: RoutePaths.data, icon: 'info', label: 'O danych' },
]

/** Compact name and secondary features menu (DESIGN.md §6). */
export function AppHeader() {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLElement>(null)
  const menuId = useId()

  useEffect(() => {
    if (!open) return
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      setOpen(false)
      rootRef.current?.querySelector<HTMLButtonElement>('[aria-controls]')?.focus()
    }
    const onPointerDown = (e: PointerEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('keydown', onKeyDown)
    document.addEventListener('pointerdown', onPointerDown)
    return () => {
      document.removeEventListener('keydown', onKeyDown)
      document.removeEventListener('pointerdown', onPointerDown)
    }
  }, [open])

  return (
    <header ref={rootRef} className={styles.header}>
      <Link to={RoutePaths.map} className={styles.brand}>
        <h1 className={styles.name}>
          <img src={logo} alt="DefiWawa" className={styles.logo} />
        </h1>
      </Link>
      <div className={styles.menuAnchor}>
        <IconButton
          variant="floating"
          icon={open ? 'close' : 'menu'}
          label={open ? 'Zamknij menu' : 'Menu'}
          aria-expanded={open}
          aria-controls={menuId}
          onClick={() => setOpen((o) => !o)}
        />
        {open && (
          <nav id={menuId} className={styles.menu} aria-label="Menu">
            <ul>
              {MENU.map((item) => (
                <li key={item.to}>
                  <NavLink to={item.to} className={styles.item} onClick={() => setOpen(false)}>
                    <AppIcon name={item.icon} />
                    {item.label}
                  </NavLink>
                </li>
              ))}
            </ul>
          </nav>
        )}
      </div>
    </header>
  )
}
