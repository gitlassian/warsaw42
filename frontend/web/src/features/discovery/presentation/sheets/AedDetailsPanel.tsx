import { useEffect } from 'react'
import { useParams } from 'react-router'
import { buildPath } from '@/app/routePaths'
import { Button, ButtonLink } from '@/design-system/components/Button'
import { Disclosure } from '@/design-system/components/Disclosure'
import { WIDE_LAYOUT_QUERY } from '@/design-system/components/Sheet'
import { Notice } from '@/design-system/components/Notice'
import { LoadingText } from '@/design-system/components/Spinner'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { aedStatus, placementLabel } from '@/features/aeds/lib/aedStatus'
import type { Aed } from '@/features/aeds/models/aed'
import { AedHours } from '@/features/aeds/presentation/components/AedHours'
import { AedPhoto } from '@/features/aeds/presentation/components/AedPhoto'
import { AedUsageGuide } from '@/features/aeds/presentation/components/AedUsageGuide'
import { AedStatusView } from '@/features/aeds/presentation/components/AedStatusView'
import { aedsStore } from '@/features/aeds/store'
import { distanceMeters, type LngLat } from '@/shared/geo/geo'
import { useMediaQuery } from '@/shared/hooks/useMediaQuery'
import { formatDateTime, formatDistance } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import { discoveryStore, requestEtas, routeTo, startPicking } from '../../store'
import { AedList } from '../components/AedList'
import { OriginIssueNotice } from '../components/OriginIssueNotice'
import { TravelTime } from '../components/TravelTime'
import { t } from '@/i18n'

const DEVICE_CONDITION: Record<Aed['operationalStatus'], string> = {
  unknown: t('Stan urządzenia nie jest potwierdzony. Status dotyczy tylko godzin dostępu.'),
  confirmed_unavailable: t('Urządzenie jest oznaczone jako niedostępne.'),
  confirmed_operational: t('Urządzenie zostało sprawdzone.'),
}

/** Walking directions in Google Maps; without an origin it uses the device location. */
function googleMapsUrl(destination: LngLat, origin: LngLat | null) {
  const params = new URLSearchParams({ api: '1', destination: `${destination.lat},${destination.lng}`, travelmode: 'walking' })
  if (origin) params.set('origin', `${origin.lat},${origin.lng}`)
  return `https://www.google.com/maps/dir/?${params}`
}

/** Selected AED card (DESIGN.md §7): time, place, access, entrance with photo, route, details, report, then the other compared AEDs. */
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
  // On a phone the photo waits in the source details to keep the card short; the guide shows it on the way.
  const wide = useMediaQuery(WIDE_LAYOUT_QUERY)

  useEffect(() => {
    if (origin) requestEtas([id])
  }, [id, origin])

  if (!aed) {
    return aedsStatus === 'error' || aedsStatus === 'ready' ? (
      <Notice tone="warning" title={t('Nie znaleźliśmy tego defibrylatora.')} />
    ) : (
      <LoadingText>{t('Wczytujemy dane…')}</LoadingText>
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
            {t('Najszybszy z porównanych')}
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
          {t('Wejście')}
        </Text>
        <Text>{aed.entrance ?? t('Brak informacji o wejściu.')}</Text>
        <Text tone="secondary">{placementLabel(aed)}</Text>
        {wide && <AedPhoto aed={aed} />}
      </Stack>

      <Stack gap={8}>
        {routeShown ? (
          <>
            <ButtonLink variant="primary" icon="navigation" to={buildPath.navigate(aed.id)}>
              {t('Prowadź do defibrylatora')}
            </ButtonLink>
            <ButtonLink icon="google_maps" to={googleMapsUrl(aed.location, origin)} target="_blank" rel="noopener noreferrer">
              {t('Otwórz w Google Maps')}
            </ButtonLink>
          </>
        ) : (
          <Button
            variant="primary"
            icon="directions_walk"
            loading={routingState === 'loading'}
            loadingLabel={t('Wyznaczamy trasę…')}
            onClick={() => routeTo(aed.id)}
          >
            {t('Wyznacz trasę')}
          </Button>
        )}
        {routingState === 'failed' && (
          <Notice
            tone="danger"
            title={t('Nie udało się wyznaczyć trasy.')}
            actions={<Button onClick={() => routeTo(aed.id)}>{t('Spróbuj ponownie')}</Button>}
          >
            {straightLineM != null && t('Odległość w linii prostej: {distance}.', { distance: formatDistance(straightLineM) })}
          </Notice>
        )}
        {issue && (
          <OriginIssueNotice issue={issue} onPick={() => startPicking(() => routeTo(aed.id))} onRetry={() => routeTo(aed.id)} />
        )}
      </Stack>

      <div>
        <Disclosure title={t('Jak użyć defibrylatora')}>
          <AedUsageGuide withHeading={false} />
        </Disclosure>
        <Disclosure title={t('Godziny dostępu')}>
          <AedHours schedule={aed.schedule} sourceHours={aed.sourceHours} unverified={aed.unverifiedSchedule} />
        </Disclosure>
        <Disclosure title={t('Informacje ze źródła')}>
          <Text>{aed.sourceHours ?? t('Źródło nie podaje godzin.')}</Text>
          {!wide && <AedPhoto aed={aed} />}
        </Disclosure>
        <Disclosure title={t('Urządzenie i dane')}>
          <Text>{DEVICE_CONDITION[aed.operationalStatus]}</Text>
          {aed.source === 'osm' && <Text tone="secondary">{t('Punkt spoza rejestru miasta: dane z OpenStreetMap, nieoficjalne.')}</Text>}
          {aed.hoursSource === 'osm' && <Text tone="secondary">{t('Godziny z OpenStreetMap.')}</Text>}
          {aed.hoursSource === 'city_osm' && <Text tone="secondary">{t('Godziny z rejestru miasta, potwierdzone w OpenStreetMap.')}</Text>}
          {dataStatus && (
            <>
              <Text variant="meta" tone="muted">
                {t('Dane pobrano: {time}', { time: formatDateTime(dataStatus.fetchedAt) })}
              </Text>
              <Text variant="meta" tone="muted">
                {dataStatus.attribution}
              </Text>
            </>
          )}
        </Disclosure>
      </div>

      <ButtonLink to={buildPath.report(aed.id)} icon="flag">
        {t('Zgłoś problem')}
      </ButtonLink>

      {result && inResult && (
        <>
          <AedList
            title={t('Inne defibrylatory')}
            aeds={compared.filter((a) => a.id !== aed.id)}
            now={now}
            etas={etas}
            origin={origin}
          />
          <AedList
            title={t('Dostęp niepotwierdzony')}
            aeds={result.unknownAccessAlternatives}
            now={now}
            etas={etas}
            origin={origin}
          />
        </>
      )}
    </Stack>
  )
}
