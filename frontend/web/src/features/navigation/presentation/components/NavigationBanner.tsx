import { useRef, type PointerEvent } from 'react'
import { AppIcon } from '@/design-system/components/AppIcon'
import { Spinner } from '@/design-system/components/Spinner'
import { placementLabel } from '@/features/aeds/lib/aedStatus'
import { aedsStore } from '@/features/aeds/store'
import { discoveryStore, rerouteFrom } from '@/features/discovery/store'
import { formatDistance } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import { maneuverIcon } from '../../lib/maneuverIcon'
import { navigationStore, previewStep } from '../../store'
import { useNavigationView } from '../useNavigationView'
import styles from './NavigationBanner.module.css'
import { t } from '@/i18n'

const SWIPE_PX = 48

/** Google Maps-style direction banner: next maneuver arrow, distance to it, instruction, and the one after. */
export function NavigationBanner() {
  const view = useNavigationView()
  const aedId = useStore(navigationStore, (s) => s.aedId)
  const position = useStore(navigationStore, (s) => s.position)
  const aed = useStore(aedsStore, (s) => (aedId ? s.byId.get(aedId) : undefined))
  const rerouting = useStore(discoveryStore, (s) => s.routing?.status === 'loading')
  const swipeX = useRef<number | null>(null)

  if (!aedId) return null

  if (!view) {
    return (
      <div className={styles.banner} role="status">
        <div className={styles.main}>
          <span className={styles.arrow}>{rerouting ? <Spinner /> : <AppIcon name="route" size={40} />}</span>
          <p className={styles.instruction}>{rerouting ? t('Wyznaczamy trasę…') : t('Brak trasy do tego defibrylatora.')}</p>
        </div>
      </div>
    )
  }

  if (view.arrived && aed) {
    return (
      <div className={styles.banner} role="status">
        <div className={styles.main}>
          <span className={styles.arrow}>
            <AppIcon name="aed" size={40} />
          </span>
          <div className={styles.text}>
            <span className={styles.distance}>{t('Jesteś na miejscu')}</span>
            <span className={styles.instruction}>{aed.entrance ?? placementLabel(aed)}</span>
          </div>
        </div>
      </div>
    )
  }

  const { steps, index, distanceM } = view
  const step = steps[index]
  const next = steps[index + 1]
  const browsable = !view.live && steps.length > 1

  const go = (i: number) => {
    if (i >= 0 && i < steps.length) previewStep(view.route, i)
  }

  // Swiping the banner sideways browses the steps, as in Google Maps.
  const onPointerDown = (e: PointerEvent) => {
    swipeX.current = e.clientX
  }
  const onPointerUp = (e: PointerEvent) => {
    if (swipeX.current === null || steps.length < 2) return
    const dx = e.clientX - swipeX.current
    swipeX.current = null
    if (Math.abs(dx) >= SWIPE_PX) go(index + (dx < 0 ? 1 : -1))
  }

  return (
    <div className={styles.stack}>
      <section
        className={styles.banner}
        aria-label={t('Wskazówki')}
        onPointerDown={onPointerDown}
        onPointerUp={onPointerUp}
        onPointerCancel={() => (swipeX.current = null)}
      >
        <div className={styles.main}>
          <span className={styles.arrow}>
            <AppIcon name={step ? maneuverIcon(step) : 'navigation'} size={40} />
          </span>
          <div className={styles.text}>
            {distanceM !== null && <span className={styles.distance}>{formatDistance(distanceM)}</span>}
            <span className={styles.instruction}>{step?.instruction ?? t('Idź wyznaczoną trasą do defibrylatora.')}</span>
          </div>
        </div>
        {/* Distance changes with every GPS fix; only the instruction is announced. */}
        <p className="visually-hidden" aria-live="polite">
          {step?.instruction}
        </p>
        {(next || browsable) && (
          <div className={styles.then}>
            {next && (
              <span className={styles.thenStep}>
                <span>{t('Następnie')}</span>
                <AppIcon name={maneuverIcon(next)} size={20} label={next.instruction} />
              </span>
            )}
            {browsable && (
              <span className={styles.pager}>
                <button type="button" className={styles.page} aria-label={t('Poprzedni krok')} disabled={index === 0} onClick={() => go(index - 1)}>
                  <AppIcon name="chevron_left" />
                </button>
                <span className={styles.count}>
                  {index + 1}/{steps.length}
                </span>
                <button
                  type="button"
                  className={styles.page}
                  aria-label={t('Następny krok')}
                  disabled={index === steps.length - 1}
                  onClick={() => go(index + 1)}
                >
                  <AppIcon name="chevron_right" />
                </button>
              </span>
            )}
          </div>
        )}
      </section>
      {view.offRoute && position && (
        <div className={styles.alert} role="alert">
          <span>{t('Zboczono z trasy')}</span>
          <button type="button" className={styles.reroute} disabled={rerouting} onClick={() => rerouteFrom(position, aedId)}>
            {rerouting ? t('Wyznaczamy…') : t('Wyznacz nową trasę')}
          </button>
        </div>
      )}
    </div>
  )
}
