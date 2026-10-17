import type { LocationIssue, Origin, WalkingRoute } from '@/features/discovery/models/routing'
import { watchPosition } from '@/features/discovery/services/geolocation'
import { discoveryStore, locate, routeTo } from '@/features/discovery/store'
import { mapCamera } from '@/features/map/lib/mapCamera'
import { createStore } from '@/shared/lib/store'
import { headingAt, planRoute, type RoutePlan } from './lib/progress.ts'

/** off: no live position (manual start point); waiting: before the first fix. */
type Tracking = 'off' | 'waiting' | 'on' | Extract<LocationIssue, 'denied' | 'unavailable' | 'insecure'>

type NavigationState = {
  aedId: string | null
  tracking: Tracking
  /** Live GPS position; the search origin stays where the route started. */
  position: Origin | null
  /** Step the user is browsing in the banner; null follows the live position. */
  previewIndex: number | null
  /** The camera follows the walker until the user pans the map. */
  following: boolean
}

export const navigationStore = createStore<NavigationState>({
  aedId: null,
  tracking: 'off',
  position: null,
  previewIndex: null,
  following: false,
})

let stopWatch: (() => void) | null = null

const plans = new WeakMap<WalkingRoute, RoutePlan>()

/** Route line measured once per route. */
export function routePlan(route: WalkingRoute): RoutePlan {
  let plan = plans.get(route)
  if (!plan) {
    plan = planRoute(route.geometry, route.steps)
    plans.set(route, plan)
  }
  return plan
}

/** Turn-by-turn mode: follows GPS when the route starts at the user's position, otherwise previews the steps. */
export function startNavigation(aedId: string) {
  stopNavigation()
  navigationStore.set({ aedId, position: null, previewIndex: 0, following: false, tracking: 'off' })
  if (discoveryStore.get().origin?.source === 'gps') return startTracking()
  const { route } = discoveryStore.get()
  if (route?.aedId === aedId) previewStep(route, 0)
}

export function startTracking() {
  stopWatch?.()
  navigationStore.set({ tracking: 'waiting', previewIndex: null, following: true })
  stopWatch = watchPosition((position) => {
    if (position === 'denied' || position === 'insecure') {
      stopWatch?.()
      stopWatch = null
      navigationStore.set({ tracking: position, previewIndex: 0, following: false })
    } else if (position === 'unavailable') {
      // Fixes often come back (tunnels, buildings): keep watching.
      navigationStore.set({ tracking: 'unavailable' })
    } else {
      navigationStore.set({ tracking: 'on', position })
    }
  })
}

export function stopNavigation() {
  stopWatch?.()
  stopWatch = null
  navigationStore.set({ aedId: null, tracking: 'off', position: null, previewIndex: null, following: false })
}

/** Shows a step in the banner and turns the map to look along it from its maneuver. */
export function previewStep(route: WalkingRoute, index: number) {
  const step = route.steps[index]
  if (!step) return
  navigationStore.set({ previewIndex: index, following: false })
  const plan = routePlan(route)
  mapCamera.navigate(step.location, plan.coordinates.length > 1 ? headingAt(plan, plan.stepAlongM[index]) : 0)
}

/** A route from a picked point: start again from the user's real position. */
export async function navigateFromHere(aedId: string) {
  if (!(await locate())) return
  await routeTo(aedId)
  startTracking()
}

/** The map's location button while navigating: back to the live position, or start from it. */
export function showMyPosition() {
  const { tracking, aedId } = navigationStore.get()
  // Not `locate()` alone: a new search origin would clear the route being walked.
  if (tracking === 'on' || tracking === 'waiting' || tracking === 'unavailable') followPosition()
  else if (aedId) navigateFromHere(aedId)
}

/** Back to the live position after browsing steps or panning the map. */
export function followPosition() {
  navigationStore.set({ previewIndex: null, following: true })
}

export function stopFollowing() {
  if (navigationStore.get().following) navigationStore.set({ following: false })
}
