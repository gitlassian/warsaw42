import mapboxgl, { type Map as MapboxMap } from 'mapbox-gl'
import { useEffect, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import type { LngLat } from '@/shared/geo/geo'

type MapMarkerProps = {
  map: MapboxMap
  lngLat: LngLat
  anchor?: 'bottom' | 'center'
  /** Raises the selected marker above its neighbours. */
  raised?: boolean
  /** Degrees clockwise from north; the marker then turns and tilts with the map (navigation arrow). */
  rotation?: number
  children: ReactNode
}

/** Renders React content as a Mapbox HTML marker. */
export function MapMarker({ map, lngLat: { lng, lat }, anchor = 'bottom', raised, rotation, children }: MapMarkerProps) {
  const [element] = useState(() => document.createElement('div'))

  useEffect(() => {
    const alignment = rotation === undefined ? 'auto' : 'map'
    const marker = new mapboxgl.Marker({ element, anchor, rotation, rotationAlignment: alignment, pitchAlignment: alignment })
      .setLngLat([lng, lat])
      .addTo(map)
    marker.getElement().style.zIndex = raised ? '2' : ''
    return () => {
      marker.remove()
    }
  }, [map, element, anchor, lng, lat, raised, rotation])

  return createPortal(children, element)
}
