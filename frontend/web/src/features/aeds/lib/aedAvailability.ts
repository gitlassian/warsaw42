import type { Aed } from '../models/aed'
import { evaluateHours } from './availability.ts'

/** Coarse state used for the map filters; `aedStatus` has the full wording. No information means unavailable. */
export type AedAvailability = 'available' | 'unavailable'

export function aedAvailability(aed: Aed, at: Date): AedAvailability {
  if (aed.operationalStatus === 'confirmed_unavailable' || aed.publicAccess !== 'public') return 'unavailable'
  return evaluateHours(aed.schedule, at).state === 'open' ? 'available' : 'unavailable'
}

/** Groups the user wants to see. With none selected there is no filter and every AED is shown. */
export type AedFilters = Record<AedAvailability, boolean>

export function passesFilters(aed: Aed, at: Date, filters: AedFilters): boolean {
  const selected = filters.available || filters.unavailable
  return !selected || filters[aedAvailability(aed, at)]
}
