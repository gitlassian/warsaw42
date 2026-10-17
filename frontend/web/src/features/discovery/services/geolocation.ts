import type { LocationIssue, Origin } from '../models/routing'

type PositionIssue = Extract<LocationIssue, 'denied' | 'unavailable' | 'insecure'>

const toOrigin = ({ coords }: GeolocationPosition): Origin => ({
  lng: coords.longitude,
  lat: coords.latitude,
  accuracyM: coords.accuracy,
  source: 'gps',
})

/** Browsers expose location only to HTTPS pages (and localhost). */
const unsupported = (): PositionIssue | null =>
  !window.isSecureContext ? 'insecure' : 'geolocation' in navigator ? null : 'unavailable'

// Checked by shape: older mobile browsers do not expose the GeolocationPositionError class.
const failed = (r: Origin | GeolocationPositionError): r is GeolocationPositionError => 'code' in r

function request(options: PositionOptions): Promise<Origin | GeolocationPositionError> {
  return new Promise((resolve) => navigator.geolocation.getCurrentPosition((p) => resolve(toOrigin(p)), resolve, options))
}

/**
 * One-shot GPS fix. Resolves with the position or the reason it is unavailable.
 * A precise fix often times out indoors or on laptops, so a failed one falls back to a coarse
 * (Wi-Fi or cached) position, which is still good enough to find nearby AEDs.
 */
export async function getCurrentPosition(): Promise<Origin | PositionIssue> {
  const issue = unsupported()
  if (issue) return issue
  const precise = await request({ enableHighAccuracy: true, timeout: 10_000, maximumAge: 30_000 })
  if (!failed(precise)) return precise
  if (precise.code === precise.PERMISSION_DENIED) return 'denied'
  const coarse = await request({ enableHighAccuracy: false, timeout: 15_000, maximumAge: 300_000 })
  if (!failed(coarse)) return coarse
  return coarse.code === coarse.PERMISSION_DENIED ? 'denied' : 'unavailable'
}

/** Continuous GPS fixes while navigating. Returns a function that stops watching. */
export function watchPosition(
  onUpdate: (position: Origin | PositionIssue) => void,
): () => void {
  const issue = unsupported()
  if (issue) {
    onUpdate(issue)
    return () => {}
  }
  const id = navigator.geolocation.watchPosition(
    (p) => onUpdate(toOrigin(p)),
    (error) => onUpdate(error.code === error.PERMISSION_DENIED ? 'denied' : 'unavailable'),
    { enableHighAccuracy: true, maximumAge: 5_000 },
  )
  return () => navigator.geolocation.clearWatch(id)
}
