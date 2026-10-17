import { EN_AEDS } from './en.aeds.ts'
import { EN_DISCOVERY } from './en.discovery.ts'
import { EN_MAP } from './en.map.ts'
import { EN_OTHER } from './en.other.ts'

/** English texts, keyed by the Polish source text passed to `t`. One table per area keeps parallel edits apart. */
const EN_CORE: Record<string, string> = {
  'Mapa defibrylatorów AED w Warszawie. Znajdź najbliższy dostępny AED i trasę pieszą.':
    'Map of AED defibrillators in Warsaw. Find the nearest available AED and a walking route.',
}

export const EN: Record<string, string> = { ...EN_CORE, ...EN_AEDS, ...EN_DISCOVERY, ...EN_MAP, ...EN_OTHER }
