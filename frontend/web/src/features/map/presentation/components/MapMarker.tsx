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
  children: ReactNode
}

/** Renders React content as a Mapbox HTML marker. */
export function MapMarker({ map, lngLat: { lng, lat }, anchor = 'bottom', raised, children }: MapMarkerProps) {
  const [element] = useState(() => document.createElement('div'))

  useEffect(() => {
    const marker = new mapboxgl.Marker({ element, anchor }).setLngLat([lng, lat]).addTo(map)
    marker.getElement().style.zIndex = raised ? '2' : ''
    return () => {
      marker.remove()
    }
  }, [map, element, anchor, lng, lat, raised])

  return createPortal(children, element)
}
