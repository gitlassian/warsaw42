import type { LocationIssue, Origin } from '../models/routing'

/** One-shot GPS fix. Resolves with the position or the reason it is unavailable. */
export function getCurrentPosition(): Promise<Origin | Extract<LocationIssue, 'denied' | 'unavailable'>> {
  return new Promise((resolve) => {
    if (!('geolocation' in navigator)) return resolve('unavailable')
    navigator.geolocation.getCurrentPosition(
      ({ coords }) =>
        resolve({ lng: coords.longitude, lat: coords.latitude, accuracyM: coords.accuracy, source: 'gps' }),
      (error) => resolve(error.code === error.PERMISSION_DENIED ? 'denied' : 'unavailable'),
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 30_000 },
    )
  })
}
