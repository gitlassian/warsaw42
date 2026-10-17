import { useNavigate } from 'react-router'
import { buildPath } from '@/app/routePaths'
import { Button } from '@/design-system/components/Button'
import { Notice } from '@/design-system/components/Notice'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { aedsStore, loadAeds } from '@/features/aeds/store'
import { formatDistance } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import type { FindResult } from '../../models/routing'
import { discoveryStore, findFrom, findNearest, startPicking } from '../../store'
import { AedList } from '../components/AedList'
import { OriginIssueNotice } from '../components/OriginIssueNotice'

/** Start screen status above the pinned find button: search outcome, location and data problems (DESIGN.md §6). */
export function StartPanel() {
  const navigate = useNavigate()
  const search = useStore(discoveryStore, (s) => s.search)
  const issue = useStore(discoveryStore, (s) => s.issue)
  const origin = useStore(discoveryStore, (s) => s.origin)
  const etas = useStore(discoveryStore, (s) => s.etas)
  const aedsStatus = useStore(aedsStore, (s) => s.status)
  const now = useStore(aedsStore, (s) => s.now)

  const showResult = (result: FindResult | null) => {
    if (result?.selected) navigate(buildPath.aed(result.selected.aed.id))
  }
  const onFind = () => findNearest().then(showResult)
  const onPick = () => startPicking((picked) => findFrom(picked).then(showResult))

  const manual = origin?.source === 'manual'
  const result = search.status === 'done' && search.result.status !== 'found' ? search.result : null
  if (!manual && !issue && search.status !== 'failed' && !result && aedsStatus !== 'error') return null

  return (
    <Stack gap={24}>
      {manual && (
        <Text variant="meta" tone="secondary">
          Szukamy od punktu wybranego na mapie.
        </Text>
      )}

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
            aeds={result.unknownAccessAlternatives}
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
    </Stack>
  )
}
