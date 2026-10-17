import { useCallback, useEffect, useRef, useState, type CSSProperties } from 'react'
import { Outlet, useLocation, useMatches, useNavigate } from 'react-router'
import type { RouteHandle } from '@/app/router'
import { RoutePaths } from '@/app/routePaths'
import { Button, ButtonLink } from '@/design-system/components/Button'
import { Notice } from '@/design-system/components/Notice'
import { Sheet, WIDE_LAYOUT_QUERY } from '@/design-system/components/Sheet'
import { nextWarsawWeekday } from '@/features/aeds/lib/viewTime'
import { formatWarsawTime } from '@/features/aeds/lib/availability'
import { aedsStore, loadAeds, resetViewTime, setTimePickerOpen, setViewTime } from '@/features/aeds/store'
import { FindButton } from '@/features/discovery/presentation/components/FindButton'
import { OriginIssueNotice } from '@/features/discovery/presentation/components/OriginIssueNotice'
import { PickOriginBanner } from '@/features/discovery/presentation/components/PickOriginBanner'
import { clearRoute, discoveryStore, locate, startPicking, stopPicking } from '@/features/discovery/store'
import { NavigationBanner } from '@/features/navigation/presentation/components/NavigationBanner'
import { useMediaQuery } from '@/shared/hooks/useMediaQuery'
import { useViewportHeight } from '@/shared/hooks/useViewportHeight'
import { useStore } from '@/shared/lib/store'
import { mapCamera } from '../../lib/mapCamera'
import { mapFiltersStore, toggleFilter } from '@/features/aeds/filterStore'
import { AppHeader, InfoButton } from '../components/AppHeader'
import { MapControls } from '../components/MapControls'
import { MapView } from '../components/MapView'
import { TimeBar } from '../components/TimeBar'
import styles from './MapPage.module.css'

/** App shell: the map stays mounted; the active route renders into the sheet / side panel; the find button is pinned. */
export function MapPage() {
  const location = useLocation()
  const navigate = useNavigate()
  const handle = useMatches().at(-1)?.handle as RouteHandle | undefined
  const viewportHeight = useViewportHeight()
  const [mapFailed, setMapFailed] = useState(false)
  // One pop-up next to the round controls at a time: the time picker or the AED filters.
  const [filtersOpen, setFiltersOpen] = useState(false)
  const onMapError = useCallback(() => setMapFailed(true), [])
  // Map bottom covered by the sheet or the pinned find bar (narrow layout only); an open sheet covers the bar.
  const [cover, setCover] = useState({ sheet: 0, dock: 0 })
  const covers = useRef(cover)
  // The sheet reports its height before the map reacts to the new route, so camera moves use the final inset.
  const updateCover = useCallback((next: Partial<typeof cover>) => {
    covers.current = { ...covers.current, ...next }
    mapCamera.setBottomInset(Math.max(covers.current.sheet, covers.current.dock))
    setCover(covers.current)
  }, [])
  const onCoverChange = useCallback((sheet: number) => updateCover({ sheet }), [updateCover])
  const picking = useStore(discoveryStore, (s) => s.picking)
  const issue = useStore(discoveryStore, (s) => s.issue)
  const locating = useStore(discoveryStore, (s) => s.locating)
  const now = useStore(aedsStore, (s) => s.now)
  const live = useStore(aedsStore, (s) => s.live)
  const available = useStore(mapFiltersStore, (s) => s.available)
  const unavailable = useStore(mapFiltersStore, (s) => s.unavailable)
  const coverageShown = location.pathname === RoutePaths.coverage
  const floating = !!handle?.floating
  const navigating = !!handle?.navigation
  const wide = useMediaQuery(WIDE_LAYOUT_QUERY)
  const dockRef = useRef<HTMLDivElement>(null)
  // Wide layout: the round controls stack above the find card, whatever its height.
  const [dockHeight, setDockHeight] = useState(0)
  const mapCover = Math.max(cover.sheet, cover.dock)
  // Navigation keeps the map clear: no round controls or time picker beside it.
  const controlsShown = !navigating && mapCover < viewportHeight * 0.7

  useEffect(() => {
    const dock = dockRef.current
    if (!dock) return
    const observer = new ResizeObserver(() => {
      setDockHeight(dock.offsetHeight)
      updateCover({ dock: wide ? 0 : dock.offsetHeight })
    })
    observer.observe(dock)
    return () => observer.disconnect()
  }, [wide, updateCover])

  useEffect(() => {
    loadAeds()
  }, [])

  // One time for the whole map; a preview stays visible in its banner after the picker closes.
  const timeOpen = useStore(aedsStore, (s) => s.pickerOpen)
  // Only one pop-up next to the round controls at a time.
  const toggleTime = () => {
    if (!timeOpen) setFiltersOpen(false)
    setTimePickerOpen(!timeOpen)
  }
  const onFiltersOpenChange = (open: boolean) => {
    if (open) setTimePickerOpen(false)
    setFiltersOpen(open)
  }

  const onClose = () => {
    if (handle?.close === 'selection') clearRoute()
    navigate(RoutePaths.map)
  }

  const onLocate = async () => {
    const origin = await locate()
    if (origin) mapCamera.focus(origin)
  }

  return (
    <div
      className={styles.layout}
      data-floating={floating || undefined}
      data-navigating={navigating || undefined}
      style={{ '--sheet-cover': `${mapCover}px`, '--dock-height': `${dockHeight}px` } as CSSProperties}
    >
      <div className={styles.header}>
        {/* Narrow: the direction banner takes the header's place at the top of the screen. */}
        {navigating && !wide ? (
          <NavigationBanner />
        ) : (
          <AppHeader floating={floating} withInfo={!wide} onClose={wide && handle?.close ? onClose : undefined} />
        )}
      </div>

      {!floating && (
        <div className={styles.panel}>
          <Sheet
            key={location.pathname}
            label="Panel"
            initialSnap={handle?.sheet}
            // The expanded sheet stops below the taller direction banner.
            topOffset={navigating ? 160 : undefined}
            onCoverChange={onCoverChange}
            onClose={!wide && handle?.close ? onClose : undefined}
          >
            <Outlet />
          </Sheet>
        </div>
      )}

      {/* Under an open sheet on narrow screens: hidden from focus and screen readers. */}
      <div ref={dockRef} className={styles.dock} inert={!floating && !wide}>
        {floating && (
          <aside className={styles.status} aria-label="Panel">
            <Outlet />
          </aside>
        )}
        {!navigating && (
          <div className={styles.find}>
            <FindButton />
          </div>
        )}
      </div>

      <div className={styles.mapArea}>
        <MapView onLoadError={onMapError} />
        <div className={styles.overlay}>
          {navigating && wide && <NavigationBanner />}
          {picking && <PickOriginBanner outside={issue === 'outside_pick'} onCancel={stopPicking} />}
          {issue && !picking && !handle?.showsLocationIssue && (
            <OriginIssueNotice issue={issue} onPick={() => startPicking()} onRetry={onLocate} />
          )}
          {!live && (
            <Notice
              tone="warning"
              title={`Podgląd: ${formatWarsawTime(now)}`}
              actions={<Button onClick={resetViewTime}>Wróć do teraz</Button>}
            >
              Mapa pokazuje dostępność o tej porze, nie teraz.
            </Notice>
          )}
          {mapFailed && (
            <Notice
              tone="danger"
              title="Nie udało się wczytać mapy."
              actions={
                <>
                  <Button onClick={() => window.location.reload()}>Spróbuj ponownie</Button>
                  <ButtonLink to={RoutePaths.aeds} icon="list">
                    Lista defibrylatorów
                  </ButtonLink>
                </>
              }
            />
          )}
        </div>
        {controlsShown && (
          <div className={styles.controls}>
            {wide && <InfoButton text="Info" />}
            <MapControls
              locating={locating}
              coverageShown={coverageShown}
              filters={{ available, unavailable }}
              onToggleFilter={toggleFilter}
              timeOpen={timeOpen}
              onToggleTime={toggleTime}
              filtersOpen={filtersOpen}
              onFiltersOpenChange={onFiltersOpenChange}
              onLocate={onLocate}
              onToggleCoverage={() => navigate(coverageShown ? RoutePaths.map : RoutePaths.coverage)}
            />
          </div>
        )}
        {timeOpen && controlsShown && (
          <div className={styles.timeBar}>
            <TimeBar
              at={now}
              live={live}
              onChange={(day, minutes) => setViewTime(nextWarsawWeekday(day, minutes, new Date()))}
              onNow={resetViewTime}
            />
          </div>
        )}
      </div>
    </div>
  )
}
