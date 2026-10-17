import { createStore } from '@/shared/lib/store'
import type { Aed, DataStatus } from './models/aed'
import { fetchAeds, fetchDataStatus } from './services/aedApi'

type AedsState = {
  status: 'idle' | 'loading' | 'ready' | 'error'
  aeds: Aed[]
  byId: Map<string, Aed>
  dataStatus: DataStatus | null
  /** Evaluation time for hours; ticks every minute so statuses follow the clock. */
  now: Date
}

export const aedsStore = createStore<AedsState>({
  status: 'idle',
  aeds: [],
  byId: new Map(),
  dataStatus: null,
  now: new Date(),
})

let clock: ReturnType<typeof setInterval> | undefined

export async function loadAeds() {
  const { status } = aedsStore.get()
  if (status === 'loading' || status === 'ready') return
  aedsStore.set({ status: 'loading' })
  clock ??= setInterval(() => aedsStore.set({ now: new Date() }), 60_000)
  try {
    const [aeds, dataStatus] = await Promise.all([fetchAeds(), fetchDataStatus()])
    aedsStore.set({ status: 'ready', aeds, byId: new Map(aeds.map((a) => [a.id, a])), dataStatus })
  } catch {
    aedsStore.set({ status: 'error' })
  }
}
