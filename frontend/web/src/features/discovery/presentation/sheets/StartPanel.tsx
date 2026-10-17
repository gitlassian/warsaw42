import { useNavigate } from 'react-router'
import { RoutePaths, buildPath } from '@/app/routePaths'
import { Button, ButtonLink } from '@/design-system/components/Button'
import { Notice } from '@/design-system/components/Notice'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { aedsStore, loadAeds } from '@/features/aeds/store'
import { formatDateTime, formatDistance } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import type { FindResult } from '../../models/routing'
import { cancelSearch, discoveryStore, findFrom, findNearest, startPicking } from '../../store'
import { AedList } from '../components/AedList'
import { OriginIssueNotice } from '../components/OriginIssueNotice'

/** Search start: one primary action, manual origin as the secondary one (DESIGN.md §6). */
export function StartPanel() {
  const navigate = useNavigate()
  const search = useStore(discoveryStore, (s) => s.search)
  const issue = useStore(discoveryStore, (s) => s.issue)
  const origin = useStore(discoveryStore, (s) => s.origin)
  const etas = useStore(discoveryStore, (s) => s.etas)
  const aedsStatus = useStore(aedsStore, (s) => s.status)
  const dataStatus = useStore(aedsStore, (s) => s.dataStatus)
  const now = useStore(aedsStore, (s) => s.now)

  const showResult = (result: FindResult | null) => {
    if (result?.selected) navigate(buildPath.aed(result.selected.aed.id))
  }
  const onFind = () => findNearest().then(showResult)
  const onPick = () => startPicking((picked) => findFrom(picked).then(showResult))

  const searching = search.status === 'searching'
  const result = search.status === 'done' && search.result.status !== 'found' ? search.result : null

  return (
    <Stack gap={24}>
      <Stack gap={8}>
        <Button variant="primary" icon="aed" loading={searching} loadingLabel="Szukamy defibrylatora…" onClick={onFind}>
          Znajdź defibrylator
        </Button>
        {searching ? (
          <Button onClick={cancelSearch}>Anuluj</Button>
        ) : (
          <Button icon="location_on" onClick={onPick}>
            Wybierz punkt na mapie
          </Button>
        )}
        {origin?.source === 'manual' && (
          <Text variant="meta" tone="secondary">
            Szukamy od punktu wybranego na mapie.
          </Text>
        )}
      </Stack>

      {issue && <OriginIssueNotice issue={issue} onPick={onPick} />}

      {search.status === 'failed' && (
        <Notice tone="danger" title="Nie udało się wyznaczyć trasy." actions={<Button onClick={onFind}>Spróbuj ponownie</Button>} />
      )}

      {result && (
        <>
          <Notice
            tone="warning"
            title={
              result.status === 'routing_unavailable'
                ? 'Nie udało się wyznaczyć trasy.'
                : 'Nie znaleźliśmy AED dostępnego według danych.'
            }
          >
            Sprawdziliśmy {result.evaluatedCount} defibrylatorów w promieniu {formatDistance(result.searchedRadiusM)}.
          </Notice>
          <AedList
            title="Dostęp niepotwierdzony"
            aeds={result.unknownAccessAlternatives.map((c) => c.aed)}
            now={now}
            etas={etas}
            origin={origin}
          />
        </>
      )}

      {aedsStatus === 'error' && (
        <Notice
          tone="danger"
          title="Nie udało się wczytać defibrylatorów."
          actions={<Button onClick={loadAeds}>Spróbuj ponownie</Button>}
        />
      )}

      {dataStatus?.sync === 'stale' && (
        <Notice tone="warning" title="Dane mogą być nieaktualne.">
          Dane pobrano: {formatDateTime(dataStatus.fetchedAt)}
        </Notice>
      )}

      <ButtonLink to={RoutePaths.aeds} icon="list">
        Defibrylatory w pobliżu
      </ButtonLink>

      <Text variant="meta" tone="muted">
        Bez logowania. Dostępność wynika z godzin podanych w danych miasta i nie potwierdza działania urządzenia.
      </Text>
    </Stack>
  )
}
