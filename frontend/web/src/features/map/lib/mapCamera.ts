import mapboxgl, { type Map as MapboxMap } from 'mapbox-gl'
import type { WalkingRoute } from '@/features/discovery/models/routing'
import type { LngLat } from '@/shared/geo/geo'

// The page has one map. Panels move the camera through this controller (only on explicit
// user actions, DESIGN.md §12) instead of holding the map instance.
let map: MapboxMap | null = null
let bottomInset = 0

// Navigation view, as in Google Maps: street level, tilted, turned to the walking direction.
const NAV_ZOOM = 19.5
const NAV_PITCH = 50
const NAV_EASE_MS = 1000

// Right side keeps targets clear of the floating map controls.
const padding = () => ({ top: 96, right: 80, bottom: bottomInset + 32, left: 32 })

export const mapCamera = {
  attach(instance: MapboxMap | null) {
    map = instance
  },

  /** Height covered by the bottom sheet, so targets stay in the visible part of the map. */
  setBottomInset(px: number) {
    bottomInset = px
  },

  focus(point: LngLat) {
    map?.easeTo({ center: point, zoom: Math.max(map.getZoom(), 16), bearing: 0, pitch: 0, padding: padding() })
  },

  /**
   * Navigation: centers `point` heading-up (`bearing`, degrees from north) and tilted.
   * The point sits in the lower part of the visible map, so more of the way ahead shows.
   */
  navigate(point: LngLat, bearing: number) {
    if (!map) return
    // The map is flat everywhere else (DESIGN.md §12); tilt is allowed only while navigating.
    map.setMaxPitch(NAV_PITCH)
    const visible = map.getContainer().clientHeight - bottomInset
    map.easeTo({
      center: point,
      zoom: NAV_ZOOM,
      bearing,
      pitch: NAV_PITCH,
      duration: NAV_EASE_MS,
      padding: { top: Math.round(visible / 2), right: 0, bottom: bottomInset, left: 0 },
    })
  },

  /** Back to the flat, north-up map after navigation. */
  exitNavigation() {
    if (!map) return
    const instance = map
    instance.easeTo({ bearing: 0, pitch: 0, padding: padding() })
    instance.once('moveend', () => instance.setMaxPitch(0))
  },

  fitRoute(route: WalkingRoute) {
    if (!map) return
    const bounds = new mapboxgl.LngLatBounds()
    route.geometry.coordinates.forEach(([lng, lat]) => bounds.extend([lng, lat]))
    map.fitBounds(bounds, { padding: padding(), maxZoom: 17, bearing: 0, pitch: 0 })
  },
}
