import type { Aed, AedSource, HoursSource, Interval, OperationalStatus, PublicAccess, Schedule } from '../models/aed'

/** One row of `public.aeds` (ENDPOINTS.md "AED data"). */
export type AedRow = {
  id: string
  object_name: string
  full_address: string
  lon: number
  lat: number
  in_building: boolean
  floor: number | null
  access_instructions: string | null
  public_access: PublicAccess
  operational_status: OperationalStatus
  hours_text: string | null
  hours_status: '24/7' | 'scheduled' | 'unknown'
  hours_verified: boolean
  hours: { weekly?: Record<string, { state: string; intervals: [number, number][] }> }
  photo_path: string | null
  source: AedSource
  hours_source: HoursSource | null
}

export const AED_COLUMNS =
  'id,object_name,full_address,lon,lat,in_building,floor,access_instructions,public_access,operational_status,hours_text,hours_status,hours_verified,hours,photo_path,source,hours_source'

/** Minutes after midnight -> "HH:MM"; 1440 becomes "24:00", which the evaluator accepts as an end. */
const clock = (minutes: number) =>
  `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`

/** Unverified hours stay unknown, and so does any weekday the database does not state (never "closed"). */
export function scheduleFromRow(row: Pick<AedRow, 'hours_status' | 'hours_verified' | 'hours'>): Schedule {
  return row.hours_verified ? parsedSchedule(row) : { kind: 'unknown' }
}

/** The stored intervals whether or not they were verified; `unknown` when nothing was parsed. */
export function parsedSchedule(row: Pick<AedRow, 'hours_status' | 'hours'>): Schedule {
  if (row.hours_status === '24/7') return { kind: 'always_open' }
  if (row.hours_status !== 'scheduled') return { kind: 'unknown' }
  const weekly = row.hours?.weekly ?? {}
  // Database weekdays are ISO 1 (Monday) to 7; the model's index 0 is Monday.
  const days = Array.from({ length: 7 }, (_, i): Interval[] | null => {
    const day = weekly[String(i + 1)]
    if (day?.state === 'open_intervals') return day.intervals.map(([start, end]): Interval => [clock(start), clock(end)])
    return day?.state === 'closed' ? [] : null
  })
  return days.every((d) => d === null) ? { kind: 'unknown' } : { kind: 'weekly', days }
}

export function aedFromRow(row: AedRow, photoUrl: (file: string) => string): Aed {
  return {
    id: row.id,
    location: { lng: row.lon, lat: row.lat },
    venueName: row.object_name,
    address: row.full_address,
    entrance: row.access_instructions,
    indoor: row.in_building,
    floor: row.floor,
    publicAccess: row.public_access,
    operationalStatus: row.operational_status,
    schedule: scheduleFromRow(row),
    unverifiedSchedule: row.hours_verified ? null : parsedSchedule(row),
    sourceHours: row.hours_text,
    sourceNote: null,
    photoUrl: row.photo_path ? photoUrl(row.photo_path) : null,
    source: row.source,
    hoursSource: row.hours_source,
  }
}
