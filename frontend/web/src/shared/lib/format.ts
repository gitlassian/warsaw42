// Polish formats in Europe/Warsaw time (DESIGN.md §8): 17.10.2026, 14:30 · 280 m · 1,2 km.
import { intlLocale, t } from '../../i18n/index.ts'

const dateTime = new Intl.DateTimeFormat(intlLocale, {
  timeZone: 'Europe/Warsaw',
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
})

const clock = new Intl.DateTimeFormat(intlLocale, { timeZone: 'Europe/Warsaw', hour: '2-digit', minute: '2-digit' })

const kilometers = new Intl.NumberFormat(intlLocale, { maximumFractionDigits: 1 })

export const formatDateTime = (date: Date | string) => dateTime.format(new Date(date))

/** 14:30 */
export const formatClock = (date: Date) => clock.format(date)

export const formatDuration = (seconds: number) => `${Math.max(1, Math.round(seconds / 60))} ${t('min')}`

export const formatDistance = (meters: number) =>
  meters < 1000 ? `${Math.round(meters / 10) * 10} ${t('m')}` : `${kilometers.format(meters / 1000)} ${t('km')}`

/** 0 = Monday, matching ISO weekday order. */
export const WEEKDAY_NAMES = [
  t('Poniedziałek'),
  t('Wtorek'),
  t('Środa'),
  t('Czwartek'),
  t('Piątek'),
  t('Sobota'),
  t('Niedziela'),
]
