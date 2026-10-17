import { useCallback, useEffect, useState, type CSSProperties } from 'react'
import { Outlet, useLocation, useMatches, useNavigate } from 'react-router'
import type { RouteHandle } from '@/app/router'
import { RoutePaths } from '@/app/routePaths'
import { Button, ButtonLink } from '@/design-system/components/Button'
import { Notice } from '@/design-system/components/Notice'
import { Sheet } from '@/design-system/components/Sheet'
import { nextWarsawWeekday } from '@/features/aeds/lib/viewTime'
import { aedsStore, loadAeds, resetViewTime, setViewTime } from '@/features/aeds/store'
import { OriginIssueNotice } from '@/features/discovery/presentation/components/OriginIssueNotice'
import { PickOriginBanner } from '@/features/discovery/presentation/components/PickOriginBanner'
import { discoveryStore, locate, startPicking, stopPicking } from '@/features/discovery/store'
import { useViewportHeight } from '@/shared/hooks/useViewportHeight'
import { useStore } from '@/shared/lib/store'
import { mapCamera } from '../../lib/mapCamera'
import { mapFiltersStore, toggleFilter } from '../../store'
import { AppHeader } from '../components/AppHeader'
import { MapControls } from '../components/MapControls'
import { MapView } from '../components/MapView'
import { TimeBar } from '../components/TimeBar'
import styles from './MapPage.module.css'

/** App shell: the map stays mounted; the active route renders into the sheet / side panel. */
export function MapPage() {
  const location = useLocation()
  const navigate = useNavigate()
  const handle = useMatches().at(-1)?.handle as RouteHandle | undefined
  const viewportHeight = useViewportHeight()
  const [cover, setCover] = useState(0)
  const [mapFailed, setMapFailed] = useState(false)
  const [timeOpen, setTimeOpen] = useState(false)
  const onMapError = useCallback(() => setMapFailed(true), [])
  // The sheet reports its height before the map reacts to the new route, so camera moves use the final inset.
  const onCoverChange = useCallback((px: number) => {
    mapCamera.setBottomInset(px)
    setCover(px)
  }, [])
  const picking = useStore(discoveryStore, (s) => s.picking)
  const issue = useStore(discoveryStore, (s) => s.issue)
  const locating = useStore(discoveryStore, (s) => s.locating)
  const now = useStore(aedsStore, (s) => s.now)
  const live = useStore(aedsStore, (s) => s.live)
  const available = useStore(mapFiltersStore, (s) => s.available)
  const unavailable = useStore(mapFiltersStore, (s) => s.unavailable)
  const unknown = useStore(mapFiltersStore, (s) => s.unknown)
  const coverageShown = location.pathname === RoutePaths.coverage

  useEffect(() => {
    loadAeds()
  }, [])

  // Closing the picker returns to the real time, so the map never keeps showing a hidden preview.
  const toggleTime = () => {
    if (timeOpen) resetViewTime()
    setTimeOpen(!timeOpen)
  }

  const onLocate = async () => {
    const origin = await locate()
    if (origin) mapCamera.focus(origin)
  }

  return (
    <div className={styles.layout} style={{ '--sheet-cover': `${cover}px` } as CSSProperties}>
      <div className={styles.header}>
        <AppHeader />
      </div>

      <div className={styles.panel}>
        <Sheet key={location.pathname} label="Panel" initialSnap={handle?.sheet} onCoverChange={onCoverChange}>
          <Outlet />
        </Sheet>
      </div>

      <div className={styles.mapArea}>
        <MapView onLoadError={onMapError} />
        <div className={styles.overlay}>
          {picking && <PickOriginBanner outside={issue === 'outside_pick'} onCancel={stopPicking} />}
          {issue && !picking && !handle?.showsLocationIssue && (
            <OriginIssueNotice issue={issue} onPick={() => startPicking()} />
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
        {cover < viewportHeight * 0.7 && (
          <div className={styles.controls}>
            <MapControls
              locating={locating}
              coverageShown={coverageShown}
              filters={{ available, unavailable, unknown }}
              onToggleFilter={toggleFilter}
              timeOpen={timeOpen}
              onToggleTime={toggleTime}
              onLocate={onLocate}
              onToggleCoverage={() => navigate(coverageShown ? RoutePaths.map : RoutePaths.coverage)}
            />
          </div>
        )}
        {cover < viewportHeight * 0.7 && (
          <>
            {timeOpen && (
              <div className={styles.timeBar}>
                <TimeBar
                  at={now}
                  live={live}
                  onChange={(day, minutes) => setViewTime(nextWarsawWeekday(day, minutes, new Date()))}
                  onNow={resetViewTime}
                />
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
