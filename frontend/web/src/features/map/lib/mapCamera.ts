import mapboxgl, { type Map as MapboxMap } from 'mapbox-gl'
import type { WalkingRoute } from '@/features/discovery/models/routing'
import type { LngLat } from '@/shared/geo/geo'

// The page has one map. Panels move the camera through this controller (only on explicit
// user actions, DESIGN.md §12) instead of holding the map instance.
let map: MapboxMap | null = null
let bottomInset = 0

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
    map?.easeTo({ center: point, zoom: Math.max(map.getZoom(), 16), padding: padding() })
  },

  fitRoute(route: WalkingRoute) {
    if (!map) return
    const bounds = new mapboxgl.LngLatBounds()
    route.geometry.coordinates.forEach(([lng, lat]) => bounds.extend([lng, lat]))
    map.fitBounds(bounds, { padding: padding(), maxZoom: 17, pitch: map.getPitch() })
  },
}
