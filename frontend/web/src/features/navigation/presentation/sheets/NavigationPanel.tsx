import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { buildPath } from '@/app/routePaths'
import { AppIcon } from '@/design-system/components/AppIcon'
import { Button } from '@/design-system/components/Button'
import { Notice } from '@/design-system/components/Notice'
import { LoadingText } from '@/design-system/components/Spinner'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { AedFindingGuide } from '@/features/aeds/presentation/components/AedFindingGuide'
import { AedUsageGuide } from '@/features/aeds/presentation/components/AedUsageGuide'
import { aedsStore } from '@/features/aeds/store'
import { discoveryStore, locate, routeTo } from '@/features/discovery/store'
import { mapCamera } from '@/features/map/lib/mapCamera'
import { formatClock, formatDistance, formatDuration } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import { maneuverIcon } from '../../lib/maneuverIcon'
import { followPosition, navigationStore, previewStep, startNavigation, startTracking, stopNavigation } from '../../store'
import { useNavigationView } from '../useNavigationView'
import styles from './NavigationPanel.module.css'

const TRACKING_NOTICE = {
  denied: 'Brak dostępu do lokalizacji. Przeglądaj kroki strzałkami na górze ekranu.',
  unavailable: 'Słaby sygnał GPS. Wskazówki wrócą, gdy pozycja się odświeży.',
  insecure: 'Lokalizacja działa tylko na stronie HTTPS. Przeglądaj kroki strzałkami na górze ekranu.',
} as const

/** Turn-by-turn mode (sheet / side panel): time left, GPS state, step list, then finding and using the AED. */
export function NavigationPanel() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const aed = useStore(aedsStore, (s) => s.byId.get(id))
  const routing = useStore(discoveryStore, (s) => (s.routing?.aedId === id ? s.routing.status : null))
  const tracking = useStore(navigationStore, (s) => s.tracking)
  const following = useStore(navigationStore, (s) => s.following)
  const view = useNavigationView()
  // Real time for the arrival estimate; the map's view time may be a preview.
  const [clock, setClock] = useState(() => Date.now())

  useEffect(() => {
    startNavigation(id)
    return () => {
      stopNavigation()
      mapCamera.exitNavigation()
    }
  }, [id])

  useEffect(() => {
    const timer = setInterval(() => setClock(Date.now()), 30_000)
    return () => clearInterval(timer)
  }, [])

  if (!aed) return <LoadingText>Wczytujemy dane…</LoadingText>

  const end = () => navigate(buildPath.aed(id))

  // A route from a picked point: start again from the user's real position.
  const fromHere = async () => {
    if (!(await locate())) return
    await routeTo(id)
    startTracking()
  }

  if (!view) {
    return (
      <Stack gap={16}>
        <Text variant="name" as="h2">
          {aed.venueName}
        </Text>
        {routing === 'loading' ? (
          <LoadingText>Wyznaczamy trasę…</LoadingText>
        ) : (
          <Notice
            tone={routing === 'failed' ? 'danger' : 'neutral'}
            title={routing === 'failed' ? 'Nie udało się wyznaczyć trasy.' : 'Najpierw wyznacz trasę.'}
            actions={
              <Button variant="primary" icon="directions_walk" onClick={() => routeTo(id)}>
                Wyznacz trasę
              </Button>
            }
          />
        )}
        <AedUsageGuide />
      </Stack>
    )
  }

  const { steps, index, arrived } = view
  const arrival = new Date(clock + view.remainingSeconds * 1000)
  const finding = <AedFindingGuide aed={aed} />
  const usage = <AedUsageGuide />

  return (
    <Stack gap={24}>
      <div className={styles.summary}>
        <div className={styles.eta}>
          <Text variant="time" tone="accent" as="p">
            {arrived ? 'Na miejscu' : formatDuration(view.remainingSeconds)}
          </Text>
          <Text variant="meta" tone="secondary">
            {arrived ? aed.venueName : `${formatDistance(view.remainingM)} · przybycie ${formatClock(arrival)}`}
          </Text>
        </div>
        <span className={styles.end}>
          <Button icon="close" onClick={end}>
            Zakończ
          </Button>
        </span>
      </div>

      {tracking === 'off' && (
        <Notice
          title="Trasa z wybranego punktu."
          actions={
            <Button icon="my_location" onClick={fromHere}>
              Prowadź z mojej lokalizacji
            </Button>
          }
        >
          Przeglądaj kroki strzałkami na górze ekranu albo wybierz krok z listy.
        </Notice>
      )}
      {tracking === 'waiting' && <LoadingText>Szukamy Twojej pozycji…</LoadingText>}
      {(tracking === 'denied' || tracking === 'unavailable' || tracking === 'insecure') && (
        <Notice tone="warning" title={TRACKING_NOTICE[tracking]} />
      )}
      {tracking === 'on' && !following && (
        <Button icon="near_me" onClick={followPosition}>
          Wróć do mojej pozycji
        </Button>
      )}

      {arrived && (
        <>
          {finding}
          {usage}
        </>
      )}

      {steps.length > 0 && (
        <section className={styles.section}>
          <Text variant="heading" as="h3">
            Wskazówki
          </Text>
          <ol className={styles.steps}>
            {steps.map((step, i) => (
              <li key={i}>
                <button
                  type="button"
                  className={styles.step}
                  aria-current={i === index ? 'step' : undefined}
                  onClick={() => previewStep(view.route, i)}
                >
                  <span className={styles.stepIcon}>
                    <AppIcon name={maneuverIcon(step)} />
                  </span>
                  <span className={styles.stepText}>
                    <span>{step.instruction}</span>
                    {step.distanceM > 0 && <span className={styles.stepMeta}>{formatDistance(step.distanceM)}</span>}
                  </span>
                </button>
              </li>
            ))}
          </ol>
        </section>
      )}

      {!arrived && (
        <>
          {finding}
          {usage}
        </>
      )}

      <Text variant="meta" tone="muted">
        Trasa: Mapbox, © OpenStreetMap. Uważaj na ruch uliczny; wskazówki mogą nie uwzględniać przejść i zamkniętych bram.
      </Text>
    </Stack>
  )
}
