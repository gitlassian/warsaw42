import { useEffect, useMemo, useState } from 'react'
import { Button } from '@/design-system/components/Button'
import { Notice } from '@/design-system/components/Notice'
import { PanelHeader } from '@/design-system/components/PanelHeader'
import { LoadingText } from '@/design-system/components/Spinner'
import { Stack } from '@/design-system/components/Stack'
import { aedStatus } from '@/features/aeds/lib/aedStatus'
import { aedsStore } from '@/features/aeds/store'
import { WARSAW_CENTER, distanceMeters } from '@/shared/geo/geo'
import { useStore } from '@/shared/lib/store'
import { discoveryStore, locate, requestEtas, startPicking } from '../../store'
import { AedList } from '../components/AedList'
import { OriginIssueNotice } from '../components/OriginIssueNotice'

const PAGE_SIZE = 20

/** Complete list access to every AED, without operating the map (DESIGN.md §7). */
export function NearbyListPanel() {
  const aeds = useStore(aedsStore, (s) => s.aeds)
  const aedsStatus = useStore(aedsStore, (s) => s.status)
  const now = useStore(aedsStore, (s) => s.now)
  const origin = useStore(discoveryStore, (s) => s.origin)
  const etas = useStore(discoveryStore, (s) => s.etas)
  const locating = useStore(discoveryStore, (s) => s.locating)
  const issue = useStore(discoveryStore, (s) => s.issue)
  const [limit, setLimit] = useState(PAGE_SIZE)

  const sorted = useMemo(() => {
    const from = origin ?? WARSAW_CENTER
    return aeds
      .map((aed) => ({ aed, distance: distanceMeters(from, aed.location) }))
      .sort((a, b) => a.distance - b.distance)
      .map((c) => c.aed)
  }, [aeds, origin])
  const shown = sorted.slice(0, limit)
  const shownKey = shown.map((a) => a.id).join()

  useEffect(() => {
    if (origin && shownKey) requestEtas(shownKey.split(','))
  }, [origin, shownKey])

  const available = shown.filter((a) => aedStatus(a, now).available)
  const others = shown.filter((a) => !aedStatus(a, now).available)

  return (
    <Stack gap={24}>
      <PanelHeader title="Defibrylatory w pobliżu" />

      {!origin && (
        <Notice
          title="Kolejność od centrum Warszawy."
          actions={
            <>
              <Button icon="my_location" loading={locating} loadingLabel="Ustalamy lokalizację…" onClick={locate}>
                Użyj mojej lokalizacji
              </Button>
              <Button icon="location_on" onClick={() => startPicking()}>
                Wybierz punkt na mapie
              </Button>
            </>
          }
        >
          Ustal punkt startowy, aby zobaczyć czas dojścia.
        </Notice>
      )}
      {issue && <OriginIssueNotice issue={issue} onPick={() => startPicking()} />}
      {aedsStatus !== 'ready' && aedsStatus !== 'error' && <LoadingText>Wczytujemy dane…</LoadingText>}

      <AedList title="Dostępne teraz" aeds={available} now={now} etas={etas} origin={origin} />
      <AedList title="Zamknięte i niedostępne" aeds={others} now={now} etas={etas} origin={origin} />

      {limit < sorted.length && <Button onClick={() => setLimit((l) => l + PAGE_SIZE)}>Pokaż więcej</Button>}
    </Stack>
  )
}
