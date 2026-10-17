// Polish is the source language and the default. English lives under /en/...: the router gets `basename: '/en'`,
// so every route and link stays the same inside the app and a language change is a full page load.
// Texts are written in Polish and passed through `t`; the English table in ./en.ts is keyed by the Polish text.
import { EN } from './en.ts'

export type Locale = 'pl' | 'en'

export const EN_PREFIX = '/en'

const hasEnPrefix = (pathname: string) => pathname === EN_PREFIX || pathname.startsWith(`${EN_PREFIX}/`)

export const localeOf = (pathname: string): Locale => (hasEnPrefix(pathname) ? 'en' : 'pl')

/** The language of this page load; it never changes without a reload. */
export const locale: Locale = typeof window === 'undefined' ? 'pl' : localeOf(window.location.pathname)

/** Router basename for the current language. */
export const basename = locale === 'en' ? EN_PREFIX : undefined

/** BCP 47 tag for Intl, Mapbox and geocoding. */
export const intlLocale = locale === 'en' ? 'en-GB' : 'pl-PL'

/** The same page in the other language: /aed/12?x -> /en/aed/12?x and back. */
export function otherLanguageHref(pathname: string, search = '', hash = ''): string {
  if (hasEnPrefix(pathname)) return `${pathname.slice(EN_PREFIX.length) || '/'}${search}${hash}`
  return `${EN_PREFIX}${pathname === '/' ? '' : pathname}${search}${hash}`
}

/** Translate a Polish text, with {placeholders} filled from the second argument: the Polish text, or its English version on /en. Missing English falls back to Polish. */
export function t(pl: string, vars?: Record<string, string | number>): string {
  const text = locale === 'en' ? (EN[pl] ?? pl) : pl
  return vars ? text.replace(/\{(\w+)\}/g, (_, key: string) => String(vars[key] ?? `{${key}}`)) : text
}
