import { useEffect, useState } from 'react'
import { buildPath } from '@/app/routePaths'
import { Button, ButtonLink } from '@/design-system/components/Button'
import { ChoiceGroup } from '@/design-system/components/ChoiceGroup'
import { Notice } from '@/design-system/components/Notice'
import { PanelHeader } from '@/design-system/components/PanelHeader'
import { RangeSlider } from '@/design-system/components/RangeSlider'
import { LoadingText } from '@/design-system/components/Spinner'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { formatWarsawTime } from '@/features/aeds/lib/availability'
import { aedsStore, setTimePickerOpen } from '@/features/aeds/store'
import { formatDistance } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import { COVERAGE_RADIUS, COVERAGE_SCENARIOS } from '../../models/coverage'
import { coverageStore, loadCoverage, setCoverageQuery } from '../../store'
import styles from './CoveragePanel.module.css'

/** "Odległość do najbliższego AED" coverage layer mode (DESIGN.md §11). */
export function CoveragePanel() {
  const scenario = useStore(coverageStore, (s) => s.scenario)
  const thresholdM = useStore(coverageStore, (s) => s.thresholdM)
  const status = useStore(coverageStore, (s) => s.status)
  const layer = useStore(coverageStore, (s) => s.layer)
  const selected = useStore(coverageStore, (s) => s.selected)
  // The slider moves freely; the layer is recalculated once it rests.
  const [radius, setRadius] = useState(thresholdM)
  useEffect(() => {
    if (radius === thresholdM) return
    const timer = setTimeout(() => setCoverageQuery({ thresholdM: radius }), 250)
    return () => clearTimeout(timer)
  }, [radius, thresholdM])
  const nearestAed = useStore(aedsStore, (s) => (selected?.nearestAedId ? s.byId.get(selected.nearestAedId) : undefined))

  // The time-based scenario follows the one map time (live: the clock); scenario changes reload on their own.
  const now = useStore(aedsStore, (s) => s.now)
  const live = useStore(aedsStore, (s) => s.live)
  useEffect(() => {
    const { scenario: current, status: loaded } = coverageStore.get()
    if (current === 'available_at' || loaded === 'idle') loadCoverage()
  }, [now])

  return (
    <Stack gap={24}>
      <Stack gap={12}>
        <PanelHeader title="Odległość do najbliższego AED" />
        {/* The legend explains the map right under the title. */}
        <ul className={styles.legend}>
          <li>
            <span className={`${styles.swatch} ${styles.covered}`} />
            Do {formatDistance(thresholdM)} od AED
          </li>
          <li>
            <span className={`${styles.swatch} ${styles.gap}`} />
            Dalej niż {formatDistance(thresholdM)}
          </li>
        </ul>
      </Stack>

      <ChoiceGroup
        legend="Scenariusz"
        options={COVERAGE_SCENARIOS}
        value={scenario}
        onChange={(value) => setCoverageQuery({ scenario: value })}
      />
      {scenario === 'available_at' && (
        <div className={styles.time}>
          <Text>Pora: {live ? 'teraz' : formatWarsawTime(now)}</Text>
          <Button variant="link" onClick={() => setTimePickerOpen(true)}>
            Zmień
          </Button>
        </div>
      )}
      <div className={styles.radius}>
        <label htmlFor="coverage-radius" className={styles.radiusLabel}>
          Promień: <strong>{formatDistance(radius)}</strong>
        </label>
        <RangeSlider
          id="coverage-radius"
          min={COVERAGE_RADIUS.min}
          max={COVERAGE_RADIUS.max}
          step={COVERAGE_RADIUS.step}
          value={radius}
          aria-valuetext={formatDistance(radius)}
          onChange={setRadius}
          minLabel={formatDistance(COVERAGE_RADIUS.min)}
          maxLabel={formatDistance(COVERAGE_RADIUS.max)}
        />
      </div>

      {status === 'loading' && <LoadingText>Obliczamy zasięg…</LoadingText>}
      {status === 'error' && (
        <Notice
          tone="danger"
          title="Nie udało się obliczyć zasięgu."
          actions={<Button onClick={loadCoverage}>Spróbuj ponownie</Button>}
        />
      )}

      {selected ? (
        <Notice title="Wybrany obszar">
          <Stack gap={4}>
            <Text>
              {selected.nearestDistanceM === null
                ? 'Brak AED spełniającego warunki scenariusza.'
                : `Najbliższy AED: ${formatDistance(selected.nearestDistanceM)} w linii prostej.`}
            </Text>
            {nearestAed && (
              <ButtonLink variant="link" to={buildPath.aed(nearestAed.id)}>
                {nearestAed.venueName}
              </ButtonLink>
            )}
          </Stack>
        </Notice>
      ) : (
        layer && <Text tone="secondary">Wybierz obszar na mapie, aby zobaczyć odległość.</Text>
      )}

      <Text variant="meta" tone="muted">
        Odległość w linii prostej. Dane mogą być niepełne.
      </Text>
    </Stack>
  )
}
