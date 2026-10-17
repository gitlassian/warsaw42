// Polish formats in Europe/Warsaw time (DESIGN.md §8): 17.10.2026, 14:30 · 280 m · 1,2 km.

const dateTime = new Intl.DateTimeFormat('pl-PL', {
  timeZone: 'Europe/Warsaw',
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
})

const kilometers = new Intl.NumberFormat('pl-PL', { maximumFractionDigits: 1 })

export const formatDateTime = (date: Date | string) => dateTime.format(new Date(date))

export const formatDuration = (seconds: number) => `${Math.max(1, Math.round(seconds / 60))} min`

export const formatDistance = (meters: number) =>
  meters < 1000 ? `${Math.round(meters / 10) * 10} m` : `${kilometers.format(meters / 1000)} km`

/** 0 = Monday, matching ISO weekday order. */
export const WEEKDAY_NAMES = ['Poniedziałek', 'Wtorek', 'Środa', 'Czwartek', 'Piątek', 'Sobota', 'Niedziela']
