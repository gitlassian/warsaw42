import toneClass from './tone.module.css'
import type { IconName } from './components/AppIcon'

/** Semantic color pairs (DESIGN.md §2); classes expose --tone-fg / --tone-bg. */
export type Tone = 'accent' | 'neutral' | 'warning' | 'danger'

export const TONE_ICON: Record<Tone, IconName> = {
  accent: 'check_circle',
  neutral: 'info',
  warning: 'warning',
  danger: 'error',
}

export { toneClass }
