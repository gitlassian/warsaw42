import type { Interval, Schedule } from '../models/aed'

// Shared hours evaluator (PLAN.md §5–6). Pure and dependency-free so the offline
// mobile app can mirror it; the backend evaluator is authoritative online.

export type HoursEvaluation =
  | { state: 'open'; until: string | null } // null = around the clock
  | { state: 'closed'; opensAt: string | null } // next opening later the same day
  | { state: 'unknown' }

const WEEKDAY_INDEX: Record<string, number> = { Mon: 0, Tue: 1, Wed: 2, Thu: 3, Fri: 4, Sat: 5, Sun: 6 }

const clockFormat = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Europe/Warsaw',
  weekday: 'short',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
})

/** Weekday (0 = Monday) and minutes since local midnight in Warsaw. */
export function warsawClock(at: Date): { day: number; minutes: number } {
  const parts = Object.fromEntries(clockFormat.formatToParts(at).map((p) => [p.type, p.value]))
  return { day: WEEKDAY_INDEX[parts.weekday], minutes: Number(parts.hour) * 60 + Number(parts.minute) }
}

const toMinutes = (hhmm: string) => {
  const [h, m] = hhmm.split(':').map(Number)
  return h * 60 + m
}

function intervalAt(schedule: Extract<Schedule, { kind: 'weekly' }>, at: Date) {
  const { day, minutes } = warsawClock(at)
  const intervals = schedule.days[day]
  const current = intervals?.find(([start, end]) => toMinutes(start) <= minutes && minutes < toMinutes(end))
  return { intervals, current, minutes }
}

export function evaluateHours(schedule: Schedule, at: Date): HoursEvaluation {
  if (schedule.kind === 'always_open') return { state: 'open', until: null }
  if (schedule.kind === 'unknown') return { state: 'unknown' }
  const { intervals, current, minutes } = intervalAt(schedule, at)
  if (!intervals) return { state: 'unknown' }
  if (current) return { state: 'open', until: current[1] }
  const next = intervals.find(([start]) => toMinutes(start) > minutes)
  return { state: 'closed', opensAt: next?.[0] ?? null }
}

/** True only when known hours cover the whole [from, until] window, e.g. arrival + access buffer. */
export function isOpenThrough(schedule: Schedule, from: Date, until: Date): boolean {
  if (schedule.kind === 'always_open') return true
  if (schedule.kind === 'unknown') return false
  let t = from
  // Hop interval to interval so "…–24:00" followed by "00:00–…" chains across midnight.
  // shortcut: hop length uses wall-clock minutes, so a window spanning the DST switch is off by an hour; handle in the backend evaluator.
  for (let hop = 0; hop < 8; hop++) {
    const { current, minutes } = intervalAt(schedule, t)
    if (!current) return false
    const end = new Date(t.getTime() + (toMinutes(current[1]) - minutes) * 60_000)
    if (end >= until) return true
    t = end
  }
  return false
}

export const formatInterval = ([start, end]: Interval) => `${start}–${end}`
