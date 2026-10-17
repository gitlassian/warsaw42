import { createStore } from '@/shared/lib/store'
import type { Aed, DataStatus } from './models/aed'
import { fetchAeds, fetchDataStatus } from './services/aedApi'

type AedsState = {
  status: 'idle' | 'loading' | 'ready' | 'error'
  aeds: Aed[]
  byId: Map<string, Aed>
  dataStatus: DataStatus | null
  /** Evaluation time for hours; ticks every minute while `live`, otherwise the time picked on the map. */
  now: Date
  live: boolean
}

export const aedsStore = createStore<AedsState>({
  status: 'idle',
  aeds: [],
  byId: new Map(),
  dataStatus: null,
  now: new Date(),
  live: true,
})

let clock: ReturnType<typeof setInterval> | undefined

export async function loadAeds() {
  const { status } = aedsStore.get()
  if (status === 'loading' || status === 'ready') return
  aedsStore.set({ status: 'loading' })
  clock ??= setInterval(() => aedsStore.get().live && aedsStore.set({ now: new Date() }), 60_000)
  try {
    const [aeds, dataStatus] = await Promise.all([fetchAeds(), fetchDataStatus()])
    aedsStore.set({ status: 'ready', aeds, byId: new Map(aeds.map((a) => [a.id, a])), dataStatus })
  } catch {
    aedsStore.set({ status: 'error' })
  }
}

/** Preview AED availability at another time; routing still uses the real clock. */
export const setViewTime = (at: Date) => aedsStore.set({ now: at, live: false })

export const resetViewTime = () => aedsStore.set({ now: new Date(), live: true })
