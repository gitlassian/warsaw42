import { useNavigate } from 'react-router'
import { buildPath } from '@/app/routePaths'
import { Button } from '@/design-system/components/Button'
import { Notice } from '@/design-system/components/Notice'
import { Stack } from '@/design-system/components/Stack'
import { aedsStore, loadAeds } from '@/features/aeds/store'
import { formatDistance } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import type { FindResult } from '../../models/routing'
import { discoveryStore, findFrom, findNearest, startPicking } from '../../store'
import { AedList } from '../components/AedList'
import { OriginIssueNotice } from '../components/OriginIssueNotice'
import { t } from '@/i18n'

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

  const result = search.status === 'done' && search.result.status !== 'found' ? search.result : null
  if (!issue && search.status !== 'failed' && !result && aedsStatus !== 'error') return null

  return (
    <Stack gap={24}>
      {issue && <OriginIssueNotice issue={issue} onPick={onPick} onRetry={onFind} />}

      {search.status === 'failed' && (
        <Notice tone="danger" title={t('Nie udało się wyznaczyć trasy.')} actions={<Button onClick={onFind}>{t('Spróbuj ponownie')}</Button>} />
      )}

      {result && (
        <>
          <Notice
            tone="warning"
            title={
              result.status === 'routing_unavailable'
                ? t('Nie udało się wyznaczyć trasy.')
                : t('Nie znaleźliśmy AED dostępnego według danych.')
            }
          >
            {t('Sprawdziliśmy {count} defibrylatorów w promieniu {radius}.', {
              count: result.evaluatedCount,
              radius: formatDistance(result.searchedRadiusM),
            })}
          </Notice>
          <AedList
            title={t('Dostęp niepotwierdzony')}
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
          title={t('Nie udało się wczytać defibrylatorów.')}
          actions={<Button onClick={loadAeds}>{t('Spróbuj ponownie')}</Button>}
        />
      )}
    </Stack>
  )
}
