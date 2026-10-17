import type { Interval, Schedule } from '../models/aed'

/** `aeds.hours` day (ENDPOINTS.md "AED data"): minutes after midnight, Warsaw time. */
type DayHours = { state: 'open_intervals' | 'closed' | 'unknown'; intervals: [number, number][] }

export type HoursFields = {
  hours_status: '24/7' | 'scheduled' | 'unknown'
  hours_verified: boolean
  hours: { weekly?: Record<string, DayHours> }
}

const hhmm = (minutes: number) =>
  `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`

// shortcut: hours.exceptions and holiday_policy are ignored here (no row uses them on 17.10.2026);
// the server applies them in find/ETA checks. Map them into Schedule once the import fills them.
export function toSchedule({ hours_status, hours_verified, hours }: HoursFields): Schedule {
  // Same rule as the server's aed_availability: unverified hours stay unknown.
  if (!hours_verified || hours_status === 'unknown') return { kind: 'unknown' }
  if (hours_status === '24/7') return { kind: 'always_open' }
  const weekly = hours.weekly ?? {}
  return {
    kind: 'weekly',
    days: [1, 2, 3, 4, 5, 6, 7].map((weekday) => {
      const day = weekly[weekday]
      if (day?.state === 'closed') return []
      if (day?.state !== 'open_intervals') return null
      return day.intervals.map(([start, end]): Interval => [hhmm(start), hhmm(end)])
    }),
  }
}
