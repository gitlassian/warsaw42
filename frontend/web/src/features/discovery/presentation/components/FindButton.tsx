import { useNavigate } from 'react-router'
import { RoutePaths, buildPath } from '@/app/routePaths'
import { Button } from '@/design-system/components/Button'
import { Stack } from '@/design-system/components/Stack'
import { useStore } from '@/shared/lib/store'
import { cancelSearch, discoveryStore, findNearest } from '../../store'

/** "Znajdź najbliższy defibrylator": pinned on every screen, outside the sheet and panels. */
export function FindButton() {
  const navigate = useNavigate()
  const searching = useStore(discoveryStore, (s) => s.search.status === 'searching')

  const onFind = async () => {
    const result = await findNearest()
    if (result?.selected) {
      navigate(buildPath.aed(result.selected.aed.id))
      return
    }
    // "Nothing found", failures and location problems are explained on the start screen; a cancel stays put.
    const { search, issue } = discoveryStore.get()
    if (search.status !== 'idle' || issue) navigate(RoutePaths.map)
  }

  return (
    <Stack gap={8}>
      <Button variant="primary" icon="aed" loading={searching} loadingLabel="Szukamy defibrylatora…" onClick={onFind}>
        Znajdź najbliższy defibrylator
      </Button>
      {searching && <Button onClick={cancelSearch}>Anuluj</Button>}
    </Stack>
  )
}
