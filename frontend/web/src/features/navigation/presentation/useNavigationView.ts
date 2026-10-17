import { useMemo } from 'react'
import type { RouteStep, WalkingRoute } from '@/features/discovery/models/routing'
import { discoveryStore } from '@/features/discovery/store'
import { useStore } from '@/shared/lib/store'
import { hasArrived, isOffRoute, locateOnRoute, upcomingStep } from '../lib/progress.ts'
import { navigationStore, routePlan } from '../store'

export type NavigationView = {
  route: WalkingRoute
  steps: RouteStep[]
  /** Step shown in the banner. */
  index: number
  /** Meters to the shown step's maneuver; null for the start step. */
  distanceM: number | null
  remainingM: number
  remainingSeconds: number
  /** The banner follows the live position (not browsing steps). */
  live: boolean
  offRoute: boolean
  arrived: boolean
}

/** Banner and panel state for the route being navigated, or null when there is none. */
export function useNavigationView(): NavigationView | null {
  const route = useStore(discoveryStore, (s) => s.route)
  const aedId = useStore(navigationStore, (s) => s.aedId)
  const position = useStore(navigationStore, (s) => s.position)
  const previewIndex = useStore(navigationStore, (s) => s.previewIndex)

  return useMemo(() => {
    if (!route || route.aedId !== aedId) return null
    const { steps } = route
    const plan = routePlan(route)
    const progress = position && plan.coordinates.length > 1 ? locateOnRoute(plan, position) : null
    const offRoute = !!progress && isOffRoute(progress, position?.accuracyM)
    const onRoute = progress && !offRoute ? progress : null
    const live = previewIndex === null && !!onRoute
    const index = onRoute && live ? upcomingStep(plan, onRoute.alongM) : Math.min(previewIndex ?? 0, Math.max(0, steps.length - 1))
    // Provider totals are the reference; the measured line only gives the share still to walk.
    const share = onRoute && plan.totalM > 0 ? Math.max(0, 1 - onRoute.alongM / plan.totalM) : 1
    const maneuverAlongM = plan.stepAlongM[index]
    // Without steps (older backend) the banner counts down to the AED itself.
    const distanceM =
      steps.length === 0
        ? route.distanceM * share
        : onRoute && live && maneuverAlongM !== undefined
          ? Math.max(0, maneuverAlongM - onRoute.alongM)
          : index > 0
            ? steps[index - 1].distanceM
            : null
    return {
      route,
      steps,
      index,
      distanceM,
      remainingM: route.distanceM * share,
      remainingSeconds: route.durationSeconds * share,
      live,
      offRoute,
      // Browsing steps shows them even at the destination.
      arrived: live && !!onRoute && hasArrived(plan, onRoute),
    }
  }, [route, aedId, position, previewIndex])
}
