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
/** `osm`: found only in OpenStreetMap, not in the city register. */
export type AedSource = 'city' | 'osm'

/** Dataset the hours were read from; `city_osm` means OpenStreetMap confirmed the city's days. */
export type HoursSource = 'city' | 'osm' | 'city_osm'

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
  sourceNote: string | null
  /** Public photo of the cabinet (Supabase Storage); the mock snapshot has none. */
  photoUrl?: string | null
  /** Parsed from the source but not checked: shown with a warning, never used to say "open now". */
  unverifiedSchedule?: Schedule | null
  source?: AedSource
  hoursSource?: HoursSource | null
}

export type DataStatus = {
  datasetVersion: string
  /** Last successful fetch; not a physical inspection of any device. */
  fetchedAt: string
  sync: 'fresh' | 'stale' | 'unavailable'
  aedCount: number
  source: string
  license: string
}
