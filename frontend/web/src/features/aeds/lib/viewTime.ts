import { warsawClock } from './availability.ts'

// Time picker for the map: the next date (today included) on which the Warsaw wall clock shows a given weekday and time.

const wallFormat = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Europe/Warsaw',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
})

/** The Warsaw wall clock at `at`, expressed as a UTC timestamp (so its fields can be read with getUTC*). */
function wallAsUtc(at: Date): number {
  const p = Object.fromEntries(wallFormat.formatToParts(at).map((x) => [x.type, x.value]))
  return Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day), Number(p.hour), Number(p.minute))
}

const offsetMs = (at: Date) => wallAsUtc(at) - Math.floor(at.getTime() / 60_000) * 60_000

/** The instant at which the Warsaw wall clock reads year-month-day plus `minutes`; the offset is settled in two passes around DST changes. */
function warsawInstant(year: number, month: number, day: number, minutes: number): Date {
  const wall = Date.UTC(year, month - 1, day, 0, minutes)
  const first = wall - offsetMs(new Date(wall))
  return new Date(wall - offsetMs(new Date(first)))
}

/** `day`: 0 = Monday. `minutes`: since local midnight. */
export function nextWarsawWeekday(day: number, minutes: number, from: Date): Date {
  const { day: today } = warsawClock(from)
  const base = new Date(wallAsUtc(from))
  const target = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate() + ((day - today + 7) % 7)))
  return warsawInstant(target.getUTCFullYear(), target.getUTCMonth() + 1, target.getUTCDate(), minutes)
}
