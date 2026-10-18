import { useMemo } from 'react'
import { warsawClock } from '@/features/aeds/lib/availability'
import { aedsStore } from '@/features/aeds/store'
import { useStore } from '@/shared/lib/store'
import { placementView } from '../lib/placementSlots'
import { placementStore } from '../store'

/** The picks for the time shown on the map (live: the clock) and the chosen mode and count. */
export function usePlacementView() {
  const data = useStore(placementStore, (s) => s.data)
  const mode = useStore(placementStore, (s) => s.mode)
  const count = useStore(placementStore, (s) => s.count)
  const now = useStore(aedsStore, (s) => s.now)
  return useMemo(() => {
    if (!data) return null
    const { day, minutes } = warsawClock(now)
    return placementView(data, { day, minutes }, mode, count)
  }, [data, mode, count, now])
}
