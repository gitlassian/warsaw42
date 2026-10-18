/** `app_data.placement` (backend/pipeline/placement.py): where an AED helps most, for every half hour of the week. */
export type PlacementStep = [index: number, gain: number, gain65: number, cumulativePct: number]

export type PlacementSlot = {
  /** Open AEDs at that moment. */
  a: number
  /** Residents within reach of an open AED, percent. */
  c: number
  /** Residents without reach, and those aged 65+. */
  u: number
  u65: number
  /** Ranked steps: new addresses (n) and existing closed AEDs to open around the clock (v). */
  n: PlacementStep[]
  v: PlacementStep[]
}

export type PlacementData = {
  radius_m: number
  slot_minutes: number
  cost_per_aed_pln: number
  cost_basis: string
  residents: number
  population_source: string
  candidates: [lng: number, lat: number, address: string][]
  aeds: [id: string, name: string, address: string, lng: number, lat: number][]
  slots: PlacementSlot[]
}

export type PlacementMode = 'new' | 'convert'

export const PLACEMENT_MODES = [
  { value: 'new', label: 'Nowe AED w nowych miejscach' },
  { value: 'convert', label: 'Istniejące AED, zamknięte o tej porze: udostępnić całodobowo' },
] as const satisfies readonly { value: PlacementMode; label: string }[]

export const PLACEMENT_MAX_STEPS = 20

export type PlacementPick = {
  rank: number
  lng: number
  lat: number
  title: string
  address: string
  /** Residents newly within reach, and those aged 65+. */
  gain: number
  gain65: number
  cumulativePct: number
}

export type PlacementView = {
  slot: PlacementSlot
  picks: PlacementPick[]
  /** Percentage points of residents the shown picks add, and the number of residents. */
  gainPct: number
  gainPeople: number
  coveredPctAfter: number
}
