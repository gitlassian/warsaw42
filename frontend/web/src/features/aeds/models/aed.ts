import type { LngLat } from '@/shared/geo/geo'

/** Local Warsaw time "HH:MM"; "24:00" is allowed as an end. Start inclusive, end exclusive. */
export type Interval = [start: string, end: string]

/** PLAN.md §5. A day without data stays unknown; it never means closed. */
export type Schedule =
  | { kind: 'always_open' }
  | { kind: 'unknown' }
  | { kind: 'weekly'; days: (Interval[] | null)[] } // index 0 = Monday

export type PublicAccess = 'public' | 'restricted' | 'unknown'

/** Device condition, independent of opening hours (ENDPOINTS.md §1). */
export type OperationalStatus = 'unknown' | 'confirmed_unavailable' | 'confirmed_operational'

export type Aed = {
  id: string
  location: LngLat
  venueName: string
  address: string
  /** Entrance and on-site instructions from the source. */
  entrance: string | null
  indoor: boolean
  floor: number | null
  publicAccess: PublicAccess
  operationalStatus: OperationalStatus
  schedule: Schedule
  /** Original access/hours wording from Warsaw Open Data. */
  sourceHours: string | null
}

/** `app_data` key `status`. */
export type DataStatus = {
  /** Last successful import; not a physical inspection of any device. */
  fetchedAt: string
  aedCount: number
  /** Source and licence line, e.g. "Dane: m.st. Warszawa, SCB (CC BY)". */
  attribution: string
}
