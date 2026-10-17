import { WARSAW_CENTER, WARSAW_MAX_BOUNDS, isInsideWarsaw } from '@/shared/geo/geo'
import { geocodingQuery, parseAddressHits, type GeocodingResponse } from '../lib/geocoding'
import type { AddressHit } from '../models/routing'
import { locale } from '@/i18n'

// Mapbox Geocoding v6 with the public map token (the same token the map uses), limited to Warsaw.
const [[west, south], [east, north]] = WARSAW_MAX_BOUNDS

export async function searchAddresses(query: string, signal: AbortSignal): Promise<AddressHit[]> {
  const params = new URLSearchParams({
    q: geocodingQuery(query),
    access_token: import.meta.env.VITE_MAPBOX_TOKEN,
    country: 'pl',
    language: locale,
    autocomplete: 'true',
    // Nearby towns share street names: ask for more, keep five inside the city.
    limit: '10',
    types: 'address,street',
    bbox: [west, south, east, north].join(','),
    proximity: `${WARSAW_CENTER.lng},${WARSAW_CENTER.lat}`,
  })
  const response = await fetch(`https://api.mapbox.com/search/geocode/v6/forward?${params}`, { signal })
  if (!response.ok) throw new Error(`geocoding ${response.status}`)
  return parseAddressHits((await response.json()) as GeocodingResponse, isInsideWarsaw).slice(0, 5)
}
