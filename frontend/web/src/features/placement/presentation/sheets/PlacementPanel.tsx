import { useEffect } from 'react'
import { Button } from '@/design-system/components/Button'
import { ChoiceGroup } from '@/design-system/components/ChoiceGroup'
import { Disclosure } from '@/design-system/components/Disclosure'
import { Notice } from '@/design-system/components/Notice'
import { PanelHeader } from '@/design-system/components/PanelHeader'
import { RangeSlider } from '@/design-system/components/RangeSlider'
import { LoadingText } from '@/design-system/components/Spinner'
import { Stack } from '@/design-system/components/Stack'
import { Text } from '@/design-system/components/Text'
import { formatWarsawTime } from '@/features/aeds/lib/availability'
import { aedsStore, setTimePickerOpen } from '@/features/aeds/store'
import { mapCamera } from '@/features/map/lib/mapCamera'
import { formatDistance } from '@/shared/lib/format'
import { useStore } from '@/shared/lib/store'
import { PLACEMENT_MAX_STEPS, PLACEMENT_MODES } from '../../models/placement'
import { loadPlacement, placementStore, selectPlacement, setPlacementCount, setPlacementMode } from '../../store'
import { usePlacementView } from '../usePlacementView'
import styles from './PlacementPanel.module.css'

const people = new Intl.NumberFormat('pl-PL')
const zloty = (value: number) => `${people.format(value)} zł`

/** "Gdzie dodać AED": the addresses that bring the most residents within reach of an open AED at the chosen time. */
export function PlacementPanel() {
  const status = useStore(placementStore, (s) => s.status)
  const data = useStore(placementStore, (s) => s.data)
  const mode = useStore(placementStore, (s) => s.mode)
  const count = useStore(placementStore, (s) => s.count)
  const selected = useStore(placementStore, (s) => s.selected)
  const now = useStore(aedsStore, (s) => s.now)
  const live = useStore(aedsStore, (s) => s.live)
  const view = usePlacementView()

  useEffect(() => {
    loadPlacement()
  }, [])

  return (
    <Stack gap={24}>
      <Stack gap={8}>
        <PanelHeader title="Gdzie dodać AED" />
        <Text tone="secondary">
          Miejsca, które dają najwięcej mieszkańców w zasięgu otwartego AED o wybranej porze.
        </Text>
      </Stack>

      <div className={styles.time}>
        <Text>Pora: {live ? 'teraz' : formatWarsawTime(now)}</Text>
        <Button variant="link" onClick={() => setTimePickerOpen(true)}>
          Zmień
        </Button>
      </div>

      <ChoiceGroup legend="Co pokazać" options={PLACEMENT_MODES} value={mode} onChange={setPlacementMode} />

      <div className={styles.count}>
        <label htmlFor="placement-count">
          Liczba punktów: <strong>{count}</strong>
        </label>
        <RangeSlider
          id="placement-count"
          min={1}
          max={PLACEMENT_MAX_STEPS}
          step={1}
          value={count}
          onChange={setPlacementCount}
          minLabel="1"
          maxLabel={String(PLACEMENT_MAX_STEPS)}
        />
      </div>

      {status === 'loading' && <LoadingText>Wczytujemy obliczenia…</LoadingText>}
      {status === 'error' && (
        <Notice
          tone="danger"
          title="Nie udało się wczytać obliczeń."
          actions={<Button onClick={loadPlacement}>Spróbuj ponownie</Button>}
        />
      )}

      {data && view && (
        <>
          <section className={styles.summary} aria-label="Podsumowanie">
            <span className={styles.summaryLabel}>Mieszkańcy do {formatDistance(data.radius_m)} od otwartego AED</span>
            <div className={styles.headline}>
              <span className={styles.pct}>{view.slot.c}%</span>
              {view.picks.length > 0 && (
                <>
                  <span className={styles.arrow} aria-label="po zmianie">
                    →
                  </span>
                  <span className={`${styles.pct} ${styles.pctAfter}`}>{view.coveredPctAfter}%</span>
                  <span className={styles.gain}>+{view.gainPct} p.p.</span>
                </>
              )}
            </div>
            <div className={styles.bar} aria-hidden="true">
              <span className={styles.barNow} style={{ width: `${view.slot.c}%` }} />
              <span className={styles.barGain} style={{ width: `${view.coveredPctAfter - view.slot.c}%` }} />
            </div>

            <dl className={styles.facts}>
              <div>
                <dt>Otwarte AED o tej porze</dt>
                <dd>{people.format(view.slot.a)}</dd>
              </div>
              <div>
                <dt>Bez AED w zasięgu</dt>
                <dd>{people.format(view.slot.u)} osób</dd>
              </div>
              <div className={styles.sub}>
                <dt>w tym w wieku 65+</dt>
                <dd>{people.format(view.slot.u65)}</dd>
              </div>
              {view.picks.length > 0 && (
                <div className={styles.highlight}>
                  <dt>
                    Zyskuje dostęp ({count} {mode === 'new' ? 'nowych punktów' : 'udostępnionych AED'})
                  </dt>
                  <dd>+{people.format(view.gainPeople)} osób</dd>
                </div>
              )}
              {mode === 'new' && (
                <div>
                  <dt>Szacunkowy koszt</dt>
                  <dd>{zloty(count * data.cost_per_aed_pln)}</dd>
                </div>
              )}
            </dl>

            <Text variant="meta" tone="secondary">
              {mode === 'new'
                ? `${count} × ${zloty(data.cost_per_aed_pln)} (${data.cost_basis}).`
                : 'Bez zakupu: wystarczy udostępnić istniejące urządzenie całą dobę, np. szafka na zewnątrz budynku.'}
            </Text>
          </section>

          {view.picks.length === 0 ? (
            <Text tone="secondary">O tej porze nie ma takich punktów.</Text>
          ) : (
            <Disclosure title={`Lista punktów (${view.picks.length})`}>
              <ol className={styles.list}>
                {view.picks.map((pick) => (
                  <li key={pick.rank}>
                    <button
                      type="button"
                      className={styles.item}
                      aria-pressed={selected === pick.rank}
                      onClick={() => {
                        selectPlacement(pick.rank)
                        mapCamera.focus({ lng: pick.lng, lat: pick.lat })
                      }}
                    >
                      <span className={styles.rank}>{pick.rank}</span>
                      <span className={styles.body}>
                        <span className={styles.title}>{pick.title}</span>
                        {mode === 'convert' && <span className={styles.meta}>{pick.address}</span>}
                        <span className={styles.stats}>
                          <span className={styles.statGain}>+{people.format(pick.gain)} osób</span>
                          <span className={styles.stat65}>65+: {people.format(pick.gain65)}</span>
                        </span>
                      </span>
                    </button>
                  </li>
                ))}
              </ol>
            </Disclosure>
          )}

          <Text variant="meta" tone="muted">
            Zasięg w linii prostej ({formatDistance(data.radius_m)}). Mieszkańcy: spis GUS 2021 rozłożony na budynki
            mieszkalne Warszawy, to szacunek do ustalania priorytetów, nie projekt rozmieszczenia.
          </Text>
        </>
      )}
    </Stack>
  )
}
