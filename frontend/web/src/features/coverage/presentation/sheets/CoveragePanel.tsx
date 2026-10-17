import { useEffect } from 'react'
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
import { COVERAGE_SCENARIOS, COVERAGE_THRESHOLDS, type CoverageScenario } from '../../models/coverage'
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
  const nearestAed = useStore(aedsStore, (s) => (selected?.nearestAedId ? s.byId.get(selected.nearestAedId) : undefined))

  useEffect(() => {
    if (coverageStore.get().status === 'idle') loadCoverage()
  }, [])

  return (
    <Stack gap={24}>
      <Stack gap={8}>
        <PanelHeader title="Zasięg AED" />
        <Text tone="secondary">Luki w dostępnych danych. Próg: {formatDistance(thresholdM)}.</Text>
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
      <ChoiceGroup
        legend="Odległość od AED"
        layout="inline"
        options={COVERAGE_THRESHOLDS}
        value={thresholdM}
        onChange={(value) => setCoverageQuery({ thresholdM: value })}
      />

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
                <span className={`${styles.swatch} ${styles.gap}`} />
                Dalej niż {formatDistance(layer.thresholdM)} od dostępnego AED
              </li>
              {layer.scenario === 'available_at' && (
                <li>
                  <span className={`${styles.swatch} ${styles.uncertain}`} />
                  Blisko są tylko AED o nieznanych godzinach
                </li>
              )}
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
        Odległość w linii prostej od środka komórki siatki {layer?.gridSizeM ?? 250} m, bez uwzględnienia przejść i barier.
        Obszary nie dowodzą braku urządzeń: dane mogą być niepełne.
      </Text>
    </Stack>
  )
}
