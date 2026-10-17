import { createStore } from '@/shared/lib/store'
import type { CoverageCell, CoverageLayer, CoverageScenario } from './models/coverage'
import { fetchCoverage } from './services/coverageApi'

type CoverageState = {
  scenario: CoverageScenario
  /** PLAN.md §9 planning assumption, not an emergency-response standard. */
  thresholdM: number
  /** Evaluation time for the `available_at` scenario. */
  at: Date
  status: 'idle' | 'loading' | 'ready' | 'error'
  /** Stays visible, with its own label, while a newer layer is calculated. */
  layer: CoverageLayer | null
  selected: CoverageCell | null
}

export const coverageStore = createStore<CoverageState>({
  scenario: 'available_at',
  thresholdM: 500,
  at: new Date(),
  status: 'idle',
  layer: null,
  selected: null,
})

let requestToken = 0

export async function loadCoverage() {
  const { scenario, thresholdM, at } = coverageStore.get()
  const token = ++requestToken
  coverageStore.set({ status: 'loading', selected: null })
  try {
    const layer = await fetchCoverage({ scenario, thresholdM, at })
    if (token === requestToken) coverageStore.set({ status: 'ready', layer })
  } catch {
    if (token === requestToken) coverageStore.set({ status: 'error' })
  }
}

export function setCoverageQuery(patch: Partial<Pick<CoverageState, 'scenario' | 'thresholdM' | 'at'>>) {
  coverageStore.set(patch)
  loadCoverage()
}

export function selectCoverageCell(cell: CoverageCell | null) {
  coverageStore.set({ selected: cell })
}
