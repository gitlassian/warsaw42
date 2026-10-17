import { createStore } from '@/shared/lib/store'
import { PLACEMENT_MAX_STEPS, type PlacementData, type PlacementMode } from './models/placement'
import { fetchPlacement } from './services/placementApi'

type PlacementState = {
  status: 'idle' | 'loading' | 'ready' | 'error'
  data: PlacementData | null
  mode: PlacementMode
  /** How many of the ranked steps the map and the list show. */
  count: number
  /** Rank of the pick highlighted in the list and on the map. */
  selected: number | null
}

export const placementStore = createStore<PlacementState>({
  status: 'idle',
  data: null,
  mode: 'new',
  count: 10,
  selected: null,
})

export async function loadPlacement() {
  if (placementStore.get().status === 'loading' || placementStore.get().status === 'ready') return
  placementStore.set({ status: 'loading' })
  try {
    placementStore.set({ status: 'ready', data: await fetchPlacement() })
  } catch {
    placementStore.set({ status: 'error' })
  }
}

export const setPlacementMode = (mode: PlacementMode) => placementStore.set({ mode, selected: null })
export const setPlacementCount = (count: number) =>
  placementStore.set({ count: Math.min(Math.max(count, 1), PLACEMENT_MAX_STEPS), selected: null })
export const selectPlacement = (rank: number | null) => placementStore.set({ selected: rank })
