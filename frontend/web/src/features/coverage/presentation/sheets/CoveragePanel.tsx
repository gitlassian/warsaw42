import { useEffect, useState } from 'react'
import { buildPath } from '@/app/routePaths'
import { Button, ButtonLink } from '@/design-system/components/Button'
import { ChoiceGroup } from '@/design-system/components/ChoiceGroup'
import { Notice } from '@/design-system/components/Notice'
import { PanelHeader } from '@/design-system/components/PanelHeader'
import { LoadingText } from '@/design-system/components/Spinner'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { TextField } from '@/design-system/components/TextField'
import { aedsStore } from '@/features/aeds/store'
import { formatDateTime, formatDistance } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import { COVERAGE_RADIUS, COVERAGE_SCENARIOS, type CoverageScenario } from '../../models/coverage'
import { coverageStore, loadCoverage, setCoverageQuery } from '../../store'
import styles from './CoveragePanel.module.css'

const scenarioLabel = (scenario: CoverageScenario) => COVERAGE_SCENARIOS.find((s) => s.value === scenario)!.label

// shortcut: datetime-local uses the browser time zone; fine for users in Warsaw, convert explicitly for remote viewers.
const toInputValue = (date: Date) => new Date(date.getTime() - date.getTimezoneOffset() * 60_000).toISOString().slice(0, 16)

/** "Zasięg AED" layer mode (DESIGN.md §11). */
export function CoveragePanel() {
  const scenario = useStore(coverageStore, (s) => s.scenario)
  const thresholdM = useStore(coverageStore, (s) => s.thresholdM)
  const at = useStore(coverageStore, (s) => s.at)
  const status = useStore(coverageStore, (s) => s.status)
  const layer = useStore(coverageStore, (s) => s.layer)
  const selected = useStore(coverageStore, (s) => s.selected)
  const dataStatus = useStore(aedsStore, (s) => s.dataStatus)
  // The slider moves freely; the layer is recalculated once it rests.
  const [radius, setRadius] = useState(thresholdM)
  useEffect(() => {
    if (radius === thresholdM) return
    const timer = setTimeout(() => setCoverageQuery({ thresholdM: radius }), 250)
    return () => clearTimeout(timer)
  }, [radius, thresholdM])
  const nearestAed = useStore(aedsStore, (s) => (selected?.nearestAedId ? s.byId.get(selected.nearestAedId) : undefined))

  // In the time-based scenario the layer follows the time picked on the map (live: the clock).
  const now = useStore(aedsStore, (s) => s.now)
  useEffect(() => {
    if (scenario === 'available_at' && coverageStore.get().at.getTime() !== now.getTime()) setCoverageQuery({ at: now })
    else if (coverageStore.get().status === 'idle') loadCoverage()
  }, [now, scenario])

  return (
    <Stack gap={24}>
      <Stack gap={8}>
        <PanelHeader title="Zasięg AED" />
        <Text tone="secondary">
          Białe koła: zasięg dostępnych AED ({formatDistance(thresholdM)}). Czerwone obszary: tam nie ma dostępnego AED w pobliżu.
        </Text>
      </Stack>

      <ChoiceGroup
        legend="Scenariusz"
        options={COVERAGE_SCENARIOS}
        value={scenario}
        onChange={(value) => setCoverageQuery({ scenario: value })}
      />
      {scenario === 'available_at' && (
        <TextField
          type="datetime-local"
          label="Data i godzina"
          value={toInputValue(at)}
          onChange={(value) => value && setCoverageQuery({ at: new Date(value) })}
        />
      )}
      <div className={styles.radius}>
        <label htmlFor="coverage-radius" className={styles.radiusLabel}>
          Odległość od AED: <strong>{formatDistance(radius)}</strong>
        </label>
        <input
          id="coverage-radius"
          type="range"
          className={styles.slider}
          min={COVERAGE_RADIUS.min}
          max={COVERAGE_RADIUS.max}
          step={COVERAGE_RADIUS.step}
          value={radius}
          aria-valuetext={formatDistance(radius)}
          onChange={(e) => setRadius(Number(e.target.value))}
        />
        <div className={styles.radiusScale} aria-hidden="true">
          <span>{formatDistance(COVERAGE_RADIUS.min)}</span>
          <span>{formatDistance(COVERAGE_RADIUS.max)}</span>
        </div>
      </div>

      {status === 'loading' && <LoadingText>Obliczamy zasięg…</LoadingText>}
      {status === 'error' && (
        <Notice
          tone="danger"
          title="Nie udało się obliczyć zasięgu."
          actions={<Button onClick={loadCoverage}>Spróbuj ponownie</Button>}
        />
      )}

      {layer && (
        <section>
          <Stack gap={8}>
            <Text variant="heading" as="h3">
              Legenda
            </Text>
            <ul className={styles.legend}>
              <li>
                <span className={`${styles.swatch} ${styles.covered}`} />
                W zasięgu {formatDistance(layer.thresholdM)} od dostępnego AED
              </li>
              <li>
                <span className={`${styles.swatch} ${styles.gap}`} />
                Dalej niż {formatDistance(layer.thresholdM)} od dostępnego AED
              </li>
            </ul>
            <Text variant="meta" tone="muted">
              Widoczna warstwa: {scenarioLabel(layer.scenario)}, {formatDateTime(layer.evaluatedAt)}
            </Text>
          </Stack>
        </section>
      )}

      {selected ? (
        <Notice title="Wybrany obszar">
          <Stack gap={4}>
            <Text>
              {selected.nearestDistanceM === null
                ? 'Brak AED spełniającego warunki scenariusza.'
                : `Najbliższy AED: ${formatDistance(selected.nearestDistanceM)} w linii prostej.`}
            </Text>
            {layer && (
              <Text variant="meta" tone="secondary">
                {scenarioLabel(layer.scenario)}, {formatDateTime(layer.evaluatedAt)}
              </Text>
            )}
            {dataStatus && (
              <Text variant="meta" tone="secondary">
                Dane pobrano: {formatDateTime(dataStatus.fetchedAt)}
              </Text>
            )}
            {nearestAed && (
              <ButtonLink variant="link" to={buildPath.aed(nearestAed.id)}>
                {nearestAed.venueName}
              </ButtonLink>
            )}
          </Stack>
        </Notice>
      ) : (
        layer && <Text tone="secondary">Wybierz zaznaczony obszar na mapie, aby zobaczyć szczegóły.</Text>
      )}

      <Text variant="meta" tone="muted">
        Koła mają promień progu w linii prostej, bez uwzględnienia przejść i barier.
        Obszary nie dowodzą braku urządzeń: dane mogą być niepełne.
      </Text>
    </Stack>
  )
}
