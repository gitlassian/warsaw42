import type { LngLat } from '../../../shared/geo/geo'
import type { AddressHit } from '../models/routing'

/** The parts of a Mapbox Geocoding v6 forward response we read. */
export type GeocodingResponse = {
  features?: {
    id?: string
    properties: {
      name: string
      place_formatted?: string
      coordinates: { longitude: number; latitude: number; routable_points?: { longitude: number; latitude: number }[] }
    }
  }[]
}

/**
 * Mapbox misses Warsaw house numbers that nearby towns share ("Marszałkowska 10") unless the query names the
 * city, but finds half-typed streets only without it. So the city is added once a house number is typed.
 */
export function geocodingQuery(query: string): string {
  return /\d/.test(query) && !/warszaw/i.test(query) ? `${query}, Warszawa` : query
}

/**
 * Suggestions inside the city only (the bounding box also reaches nearby towns). The walking route starts
 * at the address's routable point, the entrance on the street, when Mapbox gives one.
 */
export function parseAddressHits(json: GeocodingResponse, isInside: (p: LngLat) => boolean): AddressHit[] {
  return (json.features ?? []).flatMap((f, i) => {
    const { name, place_formatted, coordinates } = f.properties
    const point = coordinates.routable_points?.[0] ?? coordinates
    const location = { lng: point.longitude, lat: point.latitude }
    if (!isInside(location)) return []
    // "00-590 Warszawa, województwo mazowieckie, Polska" -> "00-590 Warszawa"
    const detail = place_formatted?.split(',')[0]?.trim() ?? null
    return [{ id: f.id ?? `${i}`, name, detail, location }]
  })
}
