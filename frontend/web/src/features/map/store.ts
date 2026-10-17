import type { AedAvailability, AedFilters } from '@/features/aeds/lib/aedAvailability'
import { createStore } from '@/shared/lib/store'

/** Which AED groups the map shows. Only the open ones by default; with every group off, all AEDs show. The selected AED always stays visible. */
export const mapFiltersStore = createStore<AedFilters>({ available: true, unavailable: false })

export const toggleFilter = (group: AedAvailability) => mapFiltersStore.set((s) => ({ [group]: !s[group] }))
