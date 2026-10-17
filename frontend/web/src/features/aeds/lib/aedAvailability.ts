import type { Aed } from '../models/aed'
import { evaluateHours } from './availability.ts'

/** Coarse state used for the map filters; `aedStatus` has the full wording. */
export type AedAvailability = 'available' | 'unavailable' | 'unknown'

export function aedAvailability(aed: Aed, at: Date): AedAvailability {
  if (aed.operationalStatus === 'confirmed_unavailable' || aed.publicAccess === 'restricted') return 'unavailable'
  if (aed.publicAccess === 'unknown') return 'unknown'
  const { state } = evaluateHours(aed.schedule, at)
  return state === 'open' ? 'available' : state === 'closed' ? 'unavailable' : 'unknown'
}

/** Groups the user wants to see. With none selected there is no filter and every AED is shown. */
export type AedFilters = Record<AedAvailability, boolean>

export function passesFilters(aed: Aed, at: Date, filters: AedFilters): boolean {
  const selected = filters.available || filters.unavailable || filters.unknown
  return !selected || filters[aedAvailability(aed, at)]
}
