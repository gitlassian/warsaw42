import { useEffect } from 'react'
import { useParams } from 'react-router'
import { buildPath } from '@/app/routePaths'
import { Button, ButtonLink } from '@/design-system/components/Button'
import { Disclosure } from '@/design-system/components/Disclosure'
import { Notice } from '@/design-system/components/Notice'
import { LoadingText } from '@/design-system/components/Spinner'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { aedStatus, placementLabel } from '@/features/aeds/lib/aedStatus'
import type { Aed } from '@/features/aeds/models/aed'
import { AedHours } from '@/features/aeds/presentation/components/AedHours'
import { AedUsageGuide } from '@/features/aeds/presentation/components/AedUsageGuide'
import { AedStatusView } from '@/features/aeds/presentation/components/AedStatusView'
import { aedsStore } from '@/features/aeds/store'
import { distanceMeters, type LngLat } from '@/shared/geo/geo'
import { formatDateTime, formatDistance } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import { discoveryStore, requestEtas, routeTo, startPicking } from '../../store'
import { AedList } from '../components/AedList'
import { OriginIssueNotice } from '../components/OriginIssueNotice'
import { TravelTime } from '../components/TravelTime'

const DEVICE_CONDITION: Record<Aed['operationalStatus'], string> = {
  unknown: 'Stan urządzenia nie jest potwierdzony. Status dotyczy tylko godzin dostępu.',
  confirmed_unavailable: 'Urządzenie jest oznaczone jako niedostępne.',
  confirmed_operational: 'Urządzenie zostało sprawdzone.',
}

/** Walking directions in Google Maps; without an origin it uses the device location. */
function googleMapsUrl(destination: LngLat, origin: LngLat | null) {
  const params = new URLSearchParams({ api: '1', destination: `${destination.lat},${destination.lng}`, travelmode: 'walking' })
  if (origin) params.set('origin', `${origin.lat},${origin.lng}`)
  return `https://www.google.com/maps/dir/?${params}`
}

/** Selected AED card (DESIGN.md §7): time, place, access, entrance, route, details, report. */
export function AedDetailsPanel() {
  const { id = '' } = useParams()
  const aed = useStore(aedsStore, (s) => s.byId.get(id))
  const aedsStatus = useStore(aedsStore, (s) => s.status)
  const dataStatus = useStore(aedsStore, (s) => s.dataStatus)
  const now = useStore(aedsStore, (s) => s.now)
  const origin = useStore(discoveryStore, (s) => s.origin)
  const etas = useStore(discoveryStore, (s) => s.etas)
  const route = useStore(discoveryStore, (s) => s.route)
  const routing = useStore(discoveryStore, (s) => s.routing)
  const search = useStore(discoveryStore, (s) => s.search)
  const issue = useStore(discoveryStore, (s) => s.issue)

  useEffect(() => {
    if (origin) requestEtas([id])
  }, [id, origin])

  if (!aed) {
    return aedsStatus === 'error' || aedsStatus === 'ready' ? (
      <Notice tone="warning" title="Nie znaleźliśmy tego defibrylatora." />
    ) : (
      <LoadingText>Wczytujemy dane…</LoadingText>
    )
  }

  // Alternatives stay visible while the user compares the AEDs of the last search.
  const result = search.status === 'done' ? search.result : null
  const compared = result ? [result.selected, ...result.alternatives].flatMap((c) => (c ? [c.aed] : [])) : []
  const inResult = compared.some((a) => a.id === aed.id)
  const fastest = result?.selected?.aed.id === aed.id
  const routeShown = route?.aedId === aed.id ? route : null
  const routingState = routing?.aedId === aed.id ? routing.status : null
  const straightLineM = origin && distanceMeters(origin, aed.location)

  return (
    <Stack gap={24}>
      <Stack gap={8}>
        {fastest && (
          <Text variant="label" tone="accent">
            Najszybszy z porównanych
          </Text>
        )}
        <TravelTime size="hero" eta={etas[aed.id]} />
        <Stack gap={4}>
          <Text variant="name" as="h2">
            {aed.venueName}
          </Text>
          <Text tone="secondary">{aed.address}</Text>
        </Stack>
      </Stack>

      <AedStatusView status={aedStatus(aed, now)} />

      <Stack gap={4}>
        <Text variant="heading" as="h3">
          Wejście
        </Text>
        <Text>{aed.entrance ?? 'Brak informacji o wejściu.'}</Text>
        <Text tone="secondary">{placementLabel(aed)}</Text>
      </Stack>

      <Stack gap={8}>
        {routeShown ? (
          <>
            <ButtonLink variant="primary" icon="navigation" to={buildPath.navigate(aed.id)}>
              Prowadź do defibrylatora
            </ButtonLink>
            <ButtonLink icon="google_maps" to={googleMapsUrl(aed.location, origin)} target="_blank" rel="noopener noreferrer">
              Otwórz w Google Maps
            </ButtonLink>
          </>
        ) : (
          <Button
            variant="primary"
            icon="directions_walk"
            loading={routingState === 'loading'}
            loadingLabel="Wyznaczamy trasę…"
            onClick={() => routeTo(aed.id)}
          >
            Wyznacz trasę
          </Button>
        )}
        {routingState === 'failed' && (
          <Notice
            tone="danger"
            title="Nie udało się wyznaczyć trasy."
            actions={<Button onClick={() => routeTo(aed.id)}>Spróbuj ponownie</Button>}
          >
            {straightLineM != null && `Odległość w linii prostej: ${formatDistance(straightLineM)}.`}
          </Notice>
        )}
        {issue && (
          <OriginIssueNotice issue={issue} onPick={() => startPicking(() => routeTo(aed.id))} onRetry={() => routeTo(aed.id)} />
        )}
      </Stack>

      {result && inResult && (
        <>
          <AedList
            title="Inne defibrylatory"
            aeds={compared.filter((a) => a.id !== aed.id)}
            now={now}
            etas={etas}
            origin={origin}
          />
          <AedList
            title="Dostęp niepotwierdzony"
            aeds={result.unknownAccessAlternatives}
            now={now}
            etas={etas}
            origin={origin}
          />
        </>
      )}

      <div>
        <Disclosure title="Jak użyć defibrylatora">
          <AedUsageGuide withHeading={false} />
        </Disclosure>
        <Disclosure title="Godziny dostępu">
          <AedHours schedule={aed.schedule} sourceHours={aed.sourceHours} unverified={aed.unverifiedSchedule} />
        </Disclosure>
        <Disclosure title="Informacje ze źródła">
          <Text>{aed.sourceHours ?? 'Źródło nie podaje godzin.'}</Text>
        </Disclosure>
        <Disclosure title="Urządzenie i dane">
          <Text>{DEVICE_CONDITION[aed.operationalStatus]}</Text>
          {aed.source === 'osm' && <Text tone="secondary">Punkt spoza rejestru miasta: dane z OpenStreetMap, nieoficjalne.</Text>}
          {aed.hoursSource === 'osm' && <Text tone="secondary">Godziny z OpenStreetMap.</Text>}
          {aed.hoursSource === 'city_osm' && <Text tone="secondary">Godziny z rejestru miasta, potwierdzone w OpenStreetMap.</Text>}
          {dataStatus && (
            <>
              <Text variant="meta" tone="muted">
                Dane pobrano: {formatDateTime(dataStatus.fetchedAt)}
              </Text>
              <Text variant="meta" tone="muted">
                {dataStatus.attribution}
              </Text>
            </>
          )}
        </Disclosure>
      </div>

      <ButtonLink to={buildPath.report(aed.id)} icon="flag">
        Zgłoś problem
      </ButtonLink>
    </Stack>
  )
}
